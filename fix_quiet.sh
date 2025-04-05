#\!/bin/bash

# Fix script to clean up any lingering 'output' function calls

# First, remove all 'output' function calls and replace with 'echo -e'
sed -i.bak2 's/output "/echo -e "/g' /Users/joshgray/git/ValigatorHealthCheck/health_check.sh

# Add the quiet mode redirection after the command line parsing
sed -i.bak3 '/^esac/a \
\
# If quiet mode is enabled, redirect all output to /dev/null\
# But save the original stdout first to restore it for the summary\
if [ "$QUIET_MODE" = true ]; then\
  exec 3>&1\
  exec 1>/dev/null 2>/dev/null\
fi' /Users/joshgray/git/ValigatorHealthCheck/health_check.sh

# Add code to restore stdout for the summary at the end
sed -i.bak4 '/^# Summary/a \
if [ "$QUIET_MODE" = true ]; then\
  # Restore stdout for the summary\
  exec 1>&3\
fi' /Users/joshgray/git/ValigatorHealthCheck/health_check.sh

echo "All fixes applied."
