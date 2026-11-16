# Output helpers for the release scripts: GitHub Actions annotations and the
# run summary.

$stdout.sync = true # Keeps progress and annotation lines in order in the CI log

def fail!(message)
  warn "::error::#{message}"
  exit 1
end

def warning!(message)
  puts "::warning::#{message}"
end

# Adds a Markdown line to the run's summary page; a no-op outside Actions.
def summary(line)
  path = ENV.fetch('GITHUB_STEP_SUMMARY', '')
  File.open(path, 'a') { |file| file.puts(line) } unless path.empty?
end
