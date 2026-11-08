require 'json'
require 'csv'

# Which findings get recorded, by Trivy result Class:
#   os-pkgs   -- CRITICAL/HIGH/UNKNOWN only. The base OS carries many MEDIUM/LOW findings with no fix
#                and no realistic path from our code; listing them all would bury what matters.
#                UNKNOWN is kept because an advisory nobody has scored yet is not a low-risk one --
#                Debian's DSA-6572-1 (ca-certificates still trusting the compromised eMudhra/emSign
#                CA hierarchy, Oct 2026) is reported by Trivy only as UNKNOWN, and a CRITICAL/HIGH
#                filter dropped it.
#   lang-pkgs -- EVERY severity (Ruby gems etc.). These are libraries our own code calls, and a
#   (and any    MEDIUM there can be directly reachable: rack's GHSA-2j8w-xcrc-x985 (MEDIUM,
#   other)      2026-10-30) made Rack::Request return a forged Host header verbatim.
# security-patch.sh therefore scans at every severity; this is where the line is drawn.
OS_SEVERITIES = %w[CRITICAL HIGH UNKNOWN].freeze

def recorded?(result, severity)
  result['Class'] == 'os-pkgs' ? OS_SEVERITIES.include?(severity) : true
end

def parse_trivy_json(output)
  # Parse Trivy JSON output and keep the findings recorded? selects (see above).
  # Expects JSON with a 'Results' key containing an array of result objects.

  data = JSON.parse(output)
  filtered_vulns = []
  results = data['Results'] || []
  return nil, 'JSON does not contain "Results" key. Ensure input is valid Trivy JSON output.' unless data['Results']

  results.each do |result|
    next unless result['Vulnerabilities'] # Skip if no vulnerabilities

    result['Vulnerabilities'].each do |vuln|
      severity = vuln['Severity']&.upcase || 'UNKNOWN'
      next unless recorded?(result, severity)

      bundler_shadowed =
        if vuln.key?('ShadowedByBundler')
          vuln['ShadowedByBundler'] ? 'yes' : 'no'
        else
          ''
        end

      filtered_vulns << {
        'Target' => result['Target'] || 'Unknown',
        'VulnerabilityID' => vuln['VulnerabilityID'] || 'N/A',
        'PkgName' => vuln['PkgName'] || 'N/A',
        'InstalledVersion' => vuln['InstalledVersion'] || 'N/A',
        'FixedVersion' => vuln['FixedVersion'] || 'N/A',
        'Severity' => severity,
        'Title' => vuln['Title'] || 'N/A',
        'PrimaryURL' => vuln['PrimaryURL'] || 'N/A',
        # Set only for gemspec findings that annotate_gem_shadowing.rb has already run against (see
        # that script, and Severance's Security/security-patch.sh where this pattern originates) --
        # whether the flagged on-disk copy is the one `bundle exec` actually loads, or a stale,
        # unreachable default-gem copy shadowed by a newer Bundler-managed version. Blank for
        # OS-package findings and any gemspec finding this wasn't run against (currently only cdeb2
        # gets annotated -- care2/yrml aren't Ruby).
        'BundlerShadowed' => bundler_shadowed,
        'BundlerShadowedDetail' => vuln['ShadowedDetail'] || ''
      }
    end
  end
  [filtered_vulns, nil]
rescue JSON::ParserError
  [nil, 'Invalid JSON format. Ensure input is valid Trivy JSON output.']
end

def write_csv_output(vulns, output_file)
  # Write filtered vulnerabilities to a CSV file for spreadsheet use.
  # A scan with nothing to report still gets a (header-only) CSV: a file that
  # exists with zero rows is a demonstrated "clean", whereas a missing file
  # can't be told apart from "never scanned" -- and it also overwrites any
  # stale CSV left over from an earlier, dirtier scan.
  headers = %w[Target VulnerabilityID Package InstalledVersion FixedVersion Severity Title
               PrimaryURL BundlerShadowed BundlerShadowedDetail]
  CSV.open(output_file, 'w') do |csv|
    csv << headers
    vulns.each do |vuln|
      csv << [
        vuln['Target'],
        vuln['VulnerabilityID'],
        vuln['PkgName'],
        vuln['InstalledVersion'],
        vuln['FixedVersion'],
        vuln['Severity'],
        vuln['Title'],
        vuln['PrimaryURL'],
        vuln['BundlerShadowed'],
        vuln['BundlerShadowedDetail']
      ]
    end
  end

  return "No recorded vulnerabilities found. Wrote header-only CSV '#{output_file}' (demonstrably zero)." if vulns.empty?

  counts = vulns.map { |v| v['Severity'] }.tally.sort_by { |s, _| %w[CRITICAL HIGH MEDIUM LOW UNKNOWN].index(s) || 9 }
  "Generated CSV file '#{output_file}' with #{vulns.length} vulnerabilities (#{counts.map { |s, n| "#{s}: #{n}" }.join(', ')})."
end

# Check for valid input
if ARGV.empty?
  puts 'Usage: ruby parse-security-scans.rb <trivy_output.json> [trivy_output2.json ...] or glob pattern (e.g., ./scans/*.json)'
  exit 1
end

# Process all files matching the provided arguments (supports glob patterns)
files = ARGV.flat_map { |arg| Dir.glob(arg) }.uniq
if files.empty?
  puts 'Error: No JSON files found matching the provided pattern(s).'
  exit 1
end

files.each do |file|
  puts "\nProcessing #{file}..."
  begin
    output = File.read(file)
  rescue Errno::ENOENT
    puts "Error: File '#{file}' not found."
    next
  end

  # Parse JSON
  vulns, error = parse_trivy_json(output)
  if error
    puts "Error for #{file}: #{error}"
    next
  end

  # Generate output CSV filename (replace .json with .csv)
  output_file = File.join(File.dirname(file), File.basename(file, '.json') + '.csv')

  # Write CSV and print result
  puts write_csv_output(vulns, output_file)
end
