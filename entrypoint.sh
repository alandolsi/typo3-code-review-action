#!/usr/bin/env bash
set -euo pipefail

INPUT_PATH="${INPUT_PATH:-.}"
INPUT_PHPCS="${INPUT_PHPCS:-true}"
INPUT_PHPCS_VERSION="${INPUT_PHPCS_VERSION:-3.9.0}"
INPUT_CODING_STANDARDS_REF="${INPUT_CODING_STANDARDS_REF:-master}"
INPUT_PHPCS_STANDARD="${INPUT_PHPCS_STANDARD:-TYPO3CMS}"
INPUT_FAIL_ON_PHPCS="${INPUT_FAIL_ON_PHPCS:-false}"
INPUT_SECURITY_CHECKS="${INPUT_SECURITY_CHECKS:-true}"
INPUT_EXCLUDE="${INPUT_EXCLUDE:-vendor,node_modules,.git}"
INPUT_SNIFFPOOL_REF="${INPUT_SNIFFPOOL_REF:-0.0.2}"
INPUT_DEBUG="${INPUT_DEBUG:-false}"

is_true() {
  local value
  value="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
  case "$value" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  echo "$value"
}

debug() {
  if is_true "$INPUT_DEBUG"; then
    echo "DEBUG: $*"
  fi
}

escape_value() {
  local value="$1"
  value="${value//'%'/'%25'}"
  value="${value//$'\n'/'%0A'}"
  value="${value//$'\r'/'%0D'}"
  echo "$value"
}

annotate() {
  local level="$1"
  local file="${2:-}"
  local line="${3:-1}"
  local col="${4:-1}"
  local message
  message="$(escape_value "$5")"

  if [[ -n "$file" ]]; then
    echo "::${level} file=${file},line=${line},col=${col}::${message}"
  else
    echo "::${level}::${message}"
  fi
}

WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
if [[ "$INPUT_PATH" = /* ]]; then
  TARGET_PATH="$INPUT_PATH"
else
  TARGET_PATH="$WORKSPACE/$INPUT_PATH"
fi

if [[ ! -d "$TARGET_PATH" ]]; then
  annotate error "" "" "" "Scan path not found: $TARGET_PATH"
  exit 1
fi

TARGET_PATH="$(cd "$TARGET_PATH" && pwd)"
debug "Target path: $TARGET_PATH"

IFS=',' read -r -a RAW_EXCLUDES <<< "$INPUT_EXCLUDE"
EXCLUDE_DIRS=()
for dir in "${RAW_EXCLUDES[@]}"; do
  dir="$(trim "$dir")"
  [[ -n "$dir" ]] && EXCLUDE_DIRS+=("$dir")
done

GREP_EXCLUDES=()
for dir in "${EXCLUDE_DIRS[@]}"; do
  GREP_EXCLUDES+=(--exclude-dir="$dir")
done

PHP_CS_IGNORE=""
for dir in "${EXCLUDE_DIRS[@]}"; do
  if [[ -n "$PHP_CS_IGNORE" ]]; then
    PHP_CS_IGNORE+=",${dir}/*"
  else
    PHP_CS_IGNORE="${dir}/*"
  fi
done

FIND_EXCLUDES=()
for dir in "${EXCLUDE_DIRS[@]}"; do
  FIND_EXCLUDES+=( ! -path "$TARGET_PATH/$dir" ! -path "$TARGET_PATH/$dir/*" )
done

HAS_PHP_FILES=false
if find "$TARGET_PATH" -type f \( -name '*.php' -o -name '*.inc' -o -name '*.phpt' \) \
  "${FIND_EXCLUDES[@]}" -print -quit | grep -q .; then
  HAS_PHP_FILES=true
fi

PHPCS_ERRORS=0
PHPCS_WARNINGS=0
SECURITY_CRITICAL=0
SECURITY_WARNINGS=0
SECURITY_NOTICES=0

if is_true "$INPUT_PHPCS"; then
  if [[ "$HAS_PHP_FILES" != "true" ]]; then
    annotate notice "" "" "" "PHPCS skipped: no PHP files found."
  else
    if ! command -v php >/dev/null 2>&1; then
      annotate error "" "" "" "PHP is required to run PHPCS."
      exit 1
    fi
    if ! command -v curl >/dev/null 2>&1; then
      annotate error "" "" "" "curl is required to download PHPCS."
      exit 1
    fi
    if ! command -v git >/dev/null 2>&1; then
      annotate error "" "" "" "git is required to download TYPO3 coding standards."
      exit 1
    fi

    TOOL_CACHE="${RUNNER_TEMP:-/tmp}/typo3-code-review"
    mkdir -p "$TOOL_CACHE"

    PHPCS_PHAR="$TOOL_CACHE/phpcs-${INPUT_PHPCS_VERSION}.phar"
    if [[ ! -f "$PHPCS_PHAR" ]]; then
      debug "Downloading PHPCS ${INPUT_PHPCS_VERSION}"
      PHPCS_URL_PRIMARY="https://github.com/PHPCSStandards/PHP_CodeSniffer/releases/download/${INPUT_PHPCS_VERSION}/phpcs.phar"
      PHPCS_URL_FALLBACK="https://github.com/squizlabs/PHP_CodeSniffer/releases/download/${INPUT_PHPCS_VERSION}/phpcs.phar"
      rm -f "$PHPCS_PHAR"
      if ! curl -fsSL -o "$PHPCS_PHAR" "$PHPCS_URL_PRIMARY"; then
        debug "Primary PHPCS URL failed, trying fallback"
        rm -f "$PHPCS_PHAR"
        if ! curl -fsSL -o "$PHPCS_PHAR" "$PHPCS_URL_FALLBACK"; then
          annotate error "" "" "" "Failed to download PHPCS ${INPUT_PHPCS_VERSION}."
          exit 1
        fi
      fi
    fi
    chmod +x "$PHPCS_PHAR"

    CS_DIR="$TOOL_CACHE/typo3cms-standard-${INPUT_CODING_STANDARDS_REF}"
    if [[ ! -d "$CS_DIR/.git" ]]; then
      debug "Downloading TYPO3CMS PHPCS standard ${INPUT_CODING_STANDARDS_REF}"
      rm -rf "$CS_DIR"
      git clone --depth 1 --branch "$INPUT_CODING_STANDARDS_REF" \
        https://github.com/beechit/TYPO3CMS.git "$CS_DIR"
    fi

    SNIFFPOOL_DIR="$TOOL_CACHE/TYPO3SniffPool-${INPUT_SNIFFPOOL_REF}"
    if [[ ! -d "$SNIFFPOOL_DIR/.git" ]]; then
      debug "Downloading TYPO3 SniffPool ${INPUT_SNIFFPOOL_REF}"
      rm -rf "$SNIFFPOOL_DIR"
      git clone --depth 1 --branch "$INPUT_SNIFFPOOL_REF" \
        https://github.com/Konafets/TYPO3SniffPool.git "$SNIFFPOOL_DIR"
    fi

    rm -rf "$CS_DIR/TYPO3SniffPool"
    ln -s "$SNIFFPOOL_DIR" "$CS_DIR/TYPO3SniffPool"

    STANDARDS_DIR="$TOOL_CACHE/phpcs-standards"
    mkdir -p "$STANDARDS_DIR"
    rm -rf "$STANDARDS_DIR/TYPO3CMS"
    ln -s "$CS_DIR" "$STANDARDS_DIR/TYPO3CMS"

    REPORT_FILE="$TOOL_CACHE/phpcs-report.json"
    PHPCS_ARGS=(
      --runtime-set installed_paths "$STANDARDS_DIR"
      --standard="$INPUT_PHPCS_STANDARD"
      --report=json
      --report-file="$REPORT_FILE"
      --extensions=php,inc,phpt
    )
    if [[ -n "$PHP_CS_IGNORE" ]]; then
      PHPCS_ARGS+=( --ignore="$PHP_CS_IGNORE" )
    fi
    PHPCS_ARGS+=( "$TARGET_PATH" -q )

    debug "Running PHPCS"
    set +e
    php "$PHPCS_PHAR" "${PHPCS_ARGS[@]}"
    PHPCS_RUN_EXIT=$?
    set -e

    if (( PHPCS_RUN_EXIT > 1 )); then
      annotate error "" "" "" "PHPCS failed with exit code ${PHPCS_RUN_EXIT}."
      exit 1
    fi

    if [[ -s "$REPORT_FILE" ]]; then
      while IFS= read -r line; do
        if [[ "$line" == TOTAL_ERRORS=* ]]; then
          PHPCS_ERRORS="${line#TOTAL_ERRORS=}"
          continue
        fi
        if [[ "$line" == TOTAL_WARNINGS=* ]]; then
          PHPCS_WARNINGS="${line#TOTAL_WARNINGS=}"
          continue
        fi
        if [[ "$line" == MSG$'\t'* ]]; then
          IFS=$'\t' read -r _ type file line_no col sniff message <<< "$line"
          if [[ "$file" == "$WORKSPACE/"* ]]; then
            file="${file#$WORKSPACE/}"
          elif [[ "$file" == "$TARGET_PATH/"* ]]; then
            file="${file#$TARGET_PATH/}"
          fi
          message="PHPCS (${sniff}): ${message}"
          if [[ "$type" == "error" ]]; then
            annotate error "$file" "$line_no" "$col" "$message"
          else
            annotate warning "$file" "$line_no" "$col" "$message"
          fi
        fi
      done < <(php -r '
$data = json_decode(file_get_contents($argv[1]), true);
$totals = $data["totals"] ?? ["errors" => 0, "warnings" => 0];
echo "TOTAL_ERRORS=" . ($totals["errors"] ?? 0) . PHP_EOL;
echo "TOTAL_WARNINGS=" . ($totals["warnings"] ?? 0) . PHP_EOL;
foreach (($data["files"] ?? []) as $file => $info) {
  foreach (($info["messages"] ?? []) as $msg) {
    $type = strtolower($msg["type"] ?? "warning");
    $line = $msg["line"] ?? 1;
    $col = $msg["column"] ?? 1;
    $sniff = $msg["source"] ?? "phpcs";
    $message = $msg["message"] ?? "PHPCS issue";
    $message = str_replace(["\r", "\n"], " ", $message);
    echo "MSG\t{$type}\t{$file}\t{$line}\t{$col}\t{$sniff}\t{$message}" . PHP_EOL;
  }
}
' "$REPORT_FILE")
    else
      annotate error "" "" "" "PHPCS report missing; no annotations produced."
    fi
  fi
fi

if is_true "$INPUT_SECURITY_CHECKS"; then
  SECURITY_PATTERNS=(
    "error|Use of eval()|\\beval\\s*\\("
    "error|Use of exec()|\\bexec\\s*\\("
    "error|Use of shell_exec()|\\bshell_exec\\s*\\("
    "error|Use of system()|\\bsystem\\s*\\("
    "error|Use of passthru()|\\bpassthru\\s*\\("
    "error|Use of proc_open()|\\bproc_open\\s*\\("
    "error|Use of popen()|\\bpopen\\s*\\("
    "error|Use of assert()|\\bassert\\s*\\("
    "warning|Use of unserialize()|\\bunserialize\\s*\\("
    "warning|Direct use of PHP superglobals|\\$_(GET|POST|REQUEST|COOKIE|FILES|SERVER)\\b"
    "notice|Deprecated TYPO3 Extbase ObjectManager|TYPO3\\\\CMS\\\\Extbase\\\\Object\\\\ObjectManager"
    "notice|Deprecated ExtensionManagementUtility::extRelPath|ExtensionManagementUtility::extRelPath"
    "notice|Deprecated GeneralUtility::makeInstanceService|GeneralUtility::makeInstanceService"
  )

  pushd "$TARGET_PATH" >/dev/null
  for entry in "${SECURITY_PATTERNS[@]}"; do
    IFS='|' read -r severity title regex <<< "$entry"
    mapfile -t matches < <(grep -R -n -E -H --binary-files=without-match \
      --include='*.php' --include='*.inc' --include='*.phpt' \
      "${GREP_EXCLUDES[@]}" -e "$regex" . || true)
    for match in "${matches[@]}"; do
      IFS=: read -r file line_no _ <<< "$match"
      file="${file#./}"
      case "$severity" in
        error)
          ((SECURITY_CRITICAL+=1))
          annotate error "$file" "$line_no" "1" "Security: ${title}"
          ;;
        warning)
          ((SECURITY_WARNINGS+=1))
          annotate warning "$file" "$line_no" "1" "Security: ${title}"
          ;;
        notice)
          ((SECURITY_NOTICES+=1))
          annotate notice "$file" "$line_no" "1" "Security: ${title}"
          ;;
      esac
    done
  done
  popd >/dev/null
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "phpcs_errors=${PHPCS_ERRORS}"
    echo "phpcs_warnings=${PHPCS_WARNINGS}"
    echo "security_critical=${SECURITY_CRITICAL}"
    echo "security_warnings=${SECURITY_WARNINGS}"
    echo "security_notices=${SECURITY_NOTICES}"
  } >> "$GITHUB_OUTPUT"
fi

EXIT_CODE=0
if (( SECURITY_CRITICAL > 0 )); then
  EXIT_CODE=1
fi
if is_true "$INPUT_FAIL_ON_PHPCS" && (( PHPCS_ERRORS > 0 )); then
  EXIT_CODE=1
fi

exit "$EXIT_CODE"
