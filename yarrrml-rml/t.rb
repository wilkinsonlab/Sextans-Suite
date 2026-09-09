#!/usr/bin/env ruby

require 'sinatra'
require 'open3'
require 'csv'
require 'fileutils'

# This service is only ever called from other containers on the same internal
# compose network, by container hostname (e.g. "yarrrml-rdfizer:4567") -- never
# "localhost". Sinatra 4.x/rack-protection 4.x enable Rack::Protection::
# HostAuthorization by default, which rejects any Host header outside a small
# built-in allowlist, so container-to-container calls got a 403 "Host not
# permitted" with zero app-level logic ever running.
#
# HostAuthorization exists to defend against DNS-rebinding attacks, where a
# *browser* is tricked into sending a request with an attacker-chosen Host
# header. There is no browser anywhere in this call path -- every caller is
# another container's own HTTP client, which fully controls its own Host
# header regardless of what this check requires. So it provides no real
# protection for a server-to-server-only service like this one; disabling it
# here costs nothing real (kept consistently disabled on cde-box-daemon too,
# for the same reason).
#
# Sinatra's own config passthrough for this (`set :protection,
# host_authorization: ...` / `except: :host_authorization`) has proven
# unreliable across versions in this codebase's sibling projects (see
# neuromuscular-disease-ontology's nmdo-search memory notes) -- both were tried
# there and failed to actually disable the check. Monkeypatching accepts?
# directly is the fix that has actually held.
require 'rack/protection/host_authorization'
class Rack::Protection::HostAuthorization
  def accepts?(_request)
    true
  end
end

# Every type gets its own work directory (/mnt/data/<type>/{tmp,triples}) so
# unrelated transforms (the CARE-SM auto-updated pipeline, a user's own custom
# datatype, the cde-box-daemon smoke test that gates the auto-update) can never
# stomp on each other's scratch files just by running around the same time --
# not full per-request locking (two triggers of the *same* type racing each
# other is still unsupported, and that's fine -- see cde-box-daemon's own
# comments), just enough that genuinely different jobs can't corrupt each
# other automatically with no human timing involved.
#
# The *source* CSV path is the one thing not fully namespaced by type: the
# CARE-SM-2 YARRRML mapping (pulled from a repo we don't own) hardcodes an
# absolute `access: /mnt/data/CARE.csv` inside itself, so both the real "CARE"
# type and cde-box-daemon's own smoke test (which runs that same mapping
# against a fixture, before trusting it) have to use that exact path. Custom
# user-authored types are unaffected by this -- their own YARRRML's `access:`
# points wherever they choose, conventionally /mnt/data/custom/<name>.csv.
CARE_MAPPING_FIXED_SOURCE_TYPES = %w[CARE _smoketest].freeze

get '/:type' do
  type = params[:type]
  # `type` reaches this point straight from the URL. It's used below to build
  # filenames and, further down, an argument to Open3.capture3 -- whitelist the
  # allowed shape up front rather than trusting arbitrary input to flow into
  # either. Open3.capture3 is also called in its array form (never touches a
  # shell regardless of content) as defense in depth on top of this check.
  # No slashes allowed -- custom datatypes address their own directory via a
  # "custom-<name>" type name instead, translated below, so this whitelist
  # never needs loosening to support them.
  halt 400, "invalid type\n" unless type =~ /\A[a-zA-Z0-9_-]+\z/

  is_custom = type.start_with?('custom-')
  custom_name = is_custom ? type.delete_prefix('custom-') : nil
  halt 400, "invalid custom type name\n" if is_custom && custom_name.empty?

  yarrrml = is_custom ? "/mnt/data/custom/#{custom_name}_yarrrml.yaml" : "/mnt/data/#{type}_yarrrml.yaml"
  input_csv_file =
    if CARE_MAPPING_FIXED_SOURCE_TYPES.include?(type)
      '/mnt/data/CARE.csv'
    elsif is_custom
      "/mnt/data/custom/#{custom_name}.csv"
    else
      "/mnt/data/#{type}.csv"
    end

  work_dir = "/mnt/data/#{type}"
  tmp_dir = File.join(work_dir, 'tmp')
  triples_dir = File.join(work_dir, 'triples')

  begin
    FileUtils.mkdir_p(triples_dir)
  rescue StandardError
    warn "triples folder coiuldn't be created.  Might already exist"
  end
  begin
    FileUtils.mkdir_p(tmp_dir)
  rescue StandardError
    warn "tmp folder coiuldn't be created.  Might already exist"
  end
  FileUtils.rm_rf(Dir.glob(File.join(tmp_dir, '*')))
  FileUtils.rm_rf(Dir.glob(File.join(triples_dir, '*')))

  # note that this routine will now ONLY work with nquads
  serialization = ENV['SERIALIZATION'] || 'nquads'
  abort "MUST USE NQUADS" unless serialization == 'nquads'
  # (nquads (default), trig, trix, jsonld, hdt, turtle)
  extension = 'rdf'
  case serialization
  when 'trig'
    extension = 'trig'
  when 'trix'
    extension = 'trix'
  when 'jsonld'
    extension = 'json'
  when 'hdt'
    extension = 'hdt'
  when 'nquads'
    extension = 'nq'
  when 'turtle'
    extension = 'ttl'
  end

  # Call the splitter with your input CSV file and desired number of lines per file
  FileUtils.cp(input_csv_file, "#{input_csv_file}_BAK")
  lines_per_file = 200
  split_csv(input_csv_file, tmp_dir, lines_per_file)

  Dir.glob(File.join(tmp_dir, '*.csv')) do |file|  # e.g. .../tmp/CARE_part_5.csv
    # Copy the file to the source location the mapping actually reads from --
    # necessary because the mapping's own `access:` is a fixed path, not
    # parameterized per chunk.
    FileUtils.cp(file, input_csv_file)

    # Execute the transformation on the copied file (uses the mapping and its
    # fixed source CSV path). Array form (not a single interpolated string) so
    # this never goes through a shell, regardless of what any of these values
    # contain.
    out, err, status = Open3.capture3('bash', 'map.sh', yarrrml, '--outputfile',
                                       File.join(tmp_dir, "#{File.basename(file)}.#{extension}"),
                                       '--serialization', serialization)
    # A silently-discarded failure here previously produced empty output with
    # no visible error anywhere -- confirmed live (a mktemp incompatibility in
    # map.sh made it fail this exact way). Always surface a non-zero exit.
    warn "map.sh failed for #{File.basename(file)} (exit #{status.exitstatus}):\n#{out}\n#{err}" unless status.success?

    puts "Copied and processed #{File.basename(file)}"
  end

  # now we should have a bunch of e.g. .../tmp/CARE_part_5.nq
  # for each of them, concatenate it to .../triples/<type>.nq
  triples_file = File.join(triples_dir, "#{type}.nq")
  Dir.glob(File.join(tmp_dir, "*.#{extension}")) do |file|
    File.open(triples_file, 'a') { |out| out.write(File.read(file)) }
  end

  # reset the original csv file
  FileUtils.cp("#{input_csv_file}_BAK", input_csv_file)
end


def split_csv(input_file, tmp_dir, lines_per_file)
  # Open the input CSV file and read its rows
  file_count = 0
  CSV.open(input_file, 'r') do |csv|
    # Get the header from the first row
    header = csv.first

    # Initialize variables to track the file splitting
    row_count = 0
    output_file = nil
    csv_writer = nil

    # Iterate over each row in the CSV file
    csv.each do |row|
      # If it's the first row of a new file, create a new CSV writer
      if row_count % lines_per_file == 0
        output_file.close if output_file
        file_count += 1
        output_filename = File.join(tmp_dir, "#{File.basename(input_file, '.csv')}_part_#{file_count}.csv")
        output_file = File.open(output_filename, 'w')
        csv_writer = CSV.new(output_file)

        # Write the header to the new file
        csv_writer << header
      end

      # Write the current row to the current output file
      csv_writer << row
      row_count += 1
    end

    # Close the final output file
    output_file.close if output_file
  end

  warn "Finished splitting the file into #{file_count} files."
end
