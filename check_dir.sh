#!/bin/bash
#
# CHECK_DIR - Nagios/Icinga plugin to monitor directory size and file count
#
# DESCRIPTION:
#   This plugin checks if a directory's size and file count are within specified thresholds.
#   It can monitor if a directory is too large, too small, has too many files, or too few files.
#
# USAGE:
#   check_dir.sh -d|--dir <directory> [-lt|--less-than|-gt|--greater-than] 
#                [-wsize <size_kb>] [-csize <size_kb>] 
#                [-wfiles <count>] [-cfiles <count>]
#
# OPTIONS:
#   -d,  --dir              Directory to check
#   -lt, --less-than        Check if values are LESS THAN thresholds (smaller is bad)
#   -gt, --greater-than     Check if values are GREATER THAN thresholds (larger is bad)
#   -wsize                  Warning threshold for directory size in KB
#   -csize                  Critical threshold for directory size in KB
#   -wfiles                 Warning threshold for file count
#   -cfiles                 Critical threshold for file count
#   -h,  --help             Show this help message
#
# EXAMPLES:
#   Check if /var/log is too large (larger than 1GB critical, 500MB warning):
#     check_dir.sh -d /var/log -gt -wsize 512000 -csize 1048576
#
#   Check if /var/backups is too small (less than 10MB critical, 50MB warning):
#     check_dir.sh -d /var/backups -lt -wsize 51200 -csize 10240
#
#   Check if /tmp has too many files (more than 1000 warning, 5000 critical):
#     check_dir.sh -d /tmp -gt -wfiles 1000 -cfiles 5000
#
#   Check if /var/spool/mail has too few files (less than 5 critical, 10 warning):
#     check_dir.sh -d /var/spool/mail -lt -wfiles 10 -cfiles 5
#
# EXIT CODES:
#   0 - OK
#   1 - WARNING
#   2 - CRITICAL
#   3 - UNKNOWN
#
# AUTHOR:
#   Mactel Team
#
# LICENSE:
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#

# Exit codes
OK=0
WARNING=1
CRITICAL=2
UNKNOWN=3

# Default values
DIRECTORY=""
WARNING_SIZE=""
CRITICAL_SIZE=""
WARNING_FILES=""
CRITICAL_FILES=""
CHECK_MODE=""

# Function to print usage
print_usage() {
    echo "Usage: $0 -d|--dir <directory> [-lt|--less-than|-gt|--greater-than]"
    echo "          [-wsize <size_kb>] [-csize <size_kb>]"
    echo "          [-wfiles <count>] [-cfiles <count>]"
    echo ""
    echo "Use '$0 --help' for more information."
}

# Function to print help
print_help() {
    cat <<EOF
CHECK_DIR - Nagios/Icinga plugin to monitor directory size and file count

DESCRIPTION:
  This plugin checks if a directory's size and file count are within specified thresholds.
  It can monitor if a directory is too large, too small, has too many files, or too few files.

USAGE:
  check_dir.sh -d|--dir <directory> [-lt|--less-than|-gt|--greater-than]
               [-wsize <size_kb>] [-csize <size_kb>]
               [-wfiles <count>] [-cfiles <count>]

OPTIONS:
  -d,  --dir              Directory to check
  -lt, --less-than        Check if values are LESS THAN thresholds (smaller is bad)
  -gt, --greater-than     Check if values are GREATER THAN thresholds (larger is bad)
  -wsize                  Warning threshold for directory size in KB
  -csize                  Critical threshold for directory size in KB
  -wfiles                 Warning threshold for file count
  -cfiles                 Critical threshold for file count
  -h,  --help             Show this help message

EXAMPLES:
  Check if /var/log is too large (larger than 1GB critical, 500MB warning):
    check_dir.sh -d /var/log -gt -wsize 512000 -csize 1048576

  Check if /var/backups is too small (less than 10MB critical, 50MB warning):
    check_dir.sh -d /var/backups -lt -wsize 51200 -csize 10240

  Check if /tmp has too many files (more than 1000 warning, 5000 critical):
    check_dir.sh -d /tmp -gt -wfiles 1000 -cfiles 5000

  Check if /var/spool/mail has too few files (less than 5 critical, 10 warning):
    check_dir.sh -d /var/spool/mail -lt -wfiles 10 -cfiles 5

EXIT CODES:
  0 - OK
  1 - WARNING
  2 - CRITICAL
  3 - UNKNOWN
EOF
}

# Parse command line options
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -d|--dir)
            DIRECTORY="$2"
            shift 2
            ;;
        -lt|--less-than)
            CHECK_MODE="lt"
            shift
            ;;
        -gt|--greater-than)
            CHECK_MODE="gt"
            shift
            ;;
        -wsize)
            WARNING_SIZE="$2"
            shift 2
            ;;
        -csize)
            CRITICAL_SIZE="$2"
            shift 2
            ;;
        -wfiles)
            WARNING_FILES="$2"
            shift 2
            ;;
        -cfiles)
            CRITICAL_FILES="$2"
            shift 2
            ;;
        -h|--help)
            print_help
            exit $OK
            ;;
        *)
            echo "Unknown option: $1"
            print_usage
            exit $UNKNOWN
            ;;
    esac
done

# Check if directory is provided
if [[ -z "$DIRECTORY" ]]; then
    echo "UNKNOWN: No directory specified."
    print_usage
    exit $UNKNOWN
fi

# Check if either -lt or -gt is specified
if [[ -z "$CHECK_MODE" ]]; then
    echo "UNKNOWN: Either -lt/--less-than or -gt/--greater-than must be specified."
    print_usage
    exit $UNKNOWN
fi

# Check if directory exists
if [[ ! -d "$DIRECTORY" ]]; then
    echo "CRITICAL: Directory '$DIRECTORY' does not exist or is not accessible."
    exit $CRITICAL
fi

# Calculate directory size in KB
DIR_SIZE=$(du -sk "$DIRECTORY" | cut -f1)
if [[ $? -ne 0 ]]; then
    echo "UNKNOWN: Could not determine directory size."
    exit $UNKNOWN
fi

# Count files in directory (including subdirectories)
FILE_COUNT=$(find "$DIRECTORY" -type f | wc -l | tr -d ' ')
if [[ $? -ne 0 ]]; then
    echo "UNKNOWN: Could not count files in directory."
    exit $UNKNOWN
fi

# Initialize status and message
STATUS=$OK
MESSAGE="Directory: $DIRECTORY, Size: $DIR_SIZE KB, Files: $FILE_COUNT"
PERFDATA="size=${DIR_SIZE}KB;${WARNING_SIZE};${CRITICAL_SIZE};0; files=${FILE_COUNT};${WARNING_FILES};${CRITICAL_FILES};0;"

# Check thresholds based on mode
if [[ "$CHECK_MODE" == "lt" ]]; then
    # For less-than mode, smaller values are bad
    if [[ -n "$CRITICAL_SIZE" ]] && [[ $DIR_SIZE -lt $CRITICAL_SIZE ]]; then
        STATUS=$CRITICAL
        MESSAGE="CRITICAL: Directory size ($DIR_SIZE KB) is below critical threshold ($CRITICAL_SIZE KB). $MESSAGE"
    elif [[ -n "$WARNING_SIZE" ]] && [[ $DIR_SIZE -lt $WARNING_SIZE ]]; then
        STATUS=$WARNING
        MESSAGE="WARNING: Directory size ($DIR_SIZE KB) is below warning threshold ($WARNING_SIZE KB). $MESSAGE"
    fi
    
    if [[ -n "$CRITICAL_FILES" ]] && [[ $FILE_COUNT -lt $CRITICAL_FILES ]]; then
        STATUS=$CRITICAL
        MESSAGE="CRITICAL: File count ($FILE_COUNT) is below critical threshold ($CRITICAL_FILES). $MESSAGE"
    elif [[ -n "$WARNING_FILES" ]] && [[ $FILE_COUNT -lt $WARNING_FILES ]]; then
        if [[ $STATUS -ne $CRITICAL ]]; then
            STATUS=$WARNING
            MESSAGE="WARNING: File count ($FILE_COUNT) is below warning threshold ($WARNING_FILES). $MESSAGE"
        fi
    fi
else
    # For greater-than mode, larger values are bad
    if [[ -n "$CRITICAL_SIZE" ]] && [[ $DIR_SIZE -gt $CRITICAL_SIZE ]]; then
        STATUS=$CRITICAL
        MESSAGE="CRITICAL: Directory size ($DIR_SIZE KB) exceeds critical threshold ($CRITICAL_SIZE KB). $MESSAGE"
    elif [[ -n "$WARNING_SIZE" ]] && [[ $DIR_SIZE -gt $WARNING_SIZE ]]; then
        STATUS=$WARNING
        MESSAGE="WARNING: Directory size ($DIR_SIZE KB) exceeds warning threshold ($WARNING_SIZE KB). $MESSAGE"
    fi
    
    if [[ -n "$CRITICAL_FILES" ]] && [[ $FILE_COUNT -gt $CRITICAL_FILES ]]; then
        STATUS=$CRITICAL
        MESSAGE="CRITICAL: File count ($FILE_COUNT) exceeds critical threshold ($CRITICAL_FILES). $MESSAGE"
    elif [[ -n "$WARNING_FILES" ]] && [[ $FILE_COUNT -gt $WARNING_FILES ]]; then
        if [[ $STATUS -ne $CRITICAL ]]; then
            STATUS=$WARNING
            MESSAGE="WARNING: File count ($FILE_COUNT) exceeds warning threshold ($WARNING_FILES). $MESSAGE"
        fi
    fi
fi

# Output result with performance data
if [[ $STATUS -eq $OK ]]; then
    echo "OK: $MESSAGE | $PERFDATA"
else
    echo "$MESSAGE | $PERFDATA"
fi

exit $STATUS