# frozen_string_literal: true

require 'inifile'
require 'json'
require 'loofah'
require 'mini_magick'
require 'net/http'
require 'optparse'
require 'uri'

INI_FILE = 'planet.ini'
AV_DIR = 'hackergotchi'
EXT_MAP = {
  'image/jpeg' => '.jpg',
  'image/png' => '.png',
  'image/webp' => '.webp',
  'image/svg+xml' => '.svg'
}.freeze

# ------------------------------------------------------------------------------
# JSON / Data & INI File Processing
# ------------------------------------------------------------------------------

def process_json_argument(options)
  {
    title: options['dsa-body'],
    feed: validate_url(options['rss-feed']),
    link: validate_url(options['site']),
    avatar: download_and_convert_image(options),
    location: validate_language_code(options['language'])
  }
end

def update_ini_with_options(options)
  ini = IniFile.load(INI_FILE) || IniFile.new(encoding: 'UTF-8')
  section_name = options[:title].downcase.gsub(/[^a-z0-9]/, '')

  ini[section_name] = get_content(
    options[:title],
    options[:feed],
    options[:link],
    options[:avatar],
    options[:location]
  )

  write_ini(ini)
end

def get_content(title, feed, link, avatar, location)
  {
    'title' => title,
    'feed' => feed,
    'link' => link,
    'location' => location,
    'avatar' => avatar
  }.compact
end

def write_ini(ini)
  sorted_ini = IniFile.new(encoding: 'UTF-8')

  ini.each_section do |section|
    next if section == 'global'

    sorted_ini[section] = ini[section]
  end

  File.open(INI_FILE, 'w') do |file|
    write_global_section(file, ini) if ini.has_section?('global')
    file.write sorted_ini.to_s
  end
end

def write_global_section(file, ini)
  file.puts '[global]'
  ini['global'].each { |key, value| file.puts "#{key} = #{value}" }
  file.puts ''
end

# ------------------------------------------------------------------------------
# Image Downloading, Formatting & Sanitization
# ------------------------------------------------------------------------------

def download_and_convert_image(options)
  avatar_input = options['avatar'].to_s.strip
  return nil if avatar_input.empty?

  uri = URI(validate_url(avatar_input))
  safe_name = options['dsa-body'].to_s.downcase.gsub(/[^a-z0-9]/, '')
  base_filename = "#{AV_DIR}/#{safe_name}"

  filename = prepare_image(uri, base_filename)
  filename = convert_and_save_other_images(base_filename, filename)
  sanitize_svg(filename)

  File.basename(filename)
end

def prepare_image(uri, base_filename)
  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
    fetch_and_write_image(http, uri, base_filename)
  end
end

def fetch_and_write_image(http, uri, base_filename)
  path = uri.path.empty? ? '/' : uri.path
  response = http.get(path)

  extension = determine_extension(uri, response)
  filename = "#{base_filename}#{extension}"

  File.open(filename, 'wb') { |file| file.write(response.body) }
  filename
end

def determine_extension(uri, response)
  extension = File.extname(uri.path)&.downcase
  return extension unless extension.nil? || extension.empty?

  EXT_MAP[response['Content-Type']] || ''
end

def convert_and_save_other_images(base_filename, filename)
  extension = File.extname(filename)&.downcase
  return filename if extension == '.svg'

  output_filename = "#{base_filename}.webp"

  image = MiniMagick::Image.open(filename)
  image.combine_options do |c|
    c.fuzz '5%'
    c.trim
    c.gravity 'center'
    c.background 'transparent'
    c.extent "#{max_side_for(image)}x#{max_side_for(image)}"
  end

  image.format 'webp'
  image.write(output_filename)

  File.delete(filename) if filename != output_filename && File.exist?(filename)
  output_filename
end

def sanitize_svg(filename)
  extension = File.extname(filename)&.downcase
  return unless extension == '.svg'

  svg_data = File.read(filename)
  sanitized_svg = Loofah.scrub_fragment(svg_data, :prune).to_s
  File.open(filename, 'w') { |file| file.write(sanitized_svg) }
end

def max_side_for(image)
  [image.width, image.height].max
end

# ------------------------------------------------------------------------------
# Input Validation Helpers
# ------------------------------------------------------------------------------

def validate_url(url)
  uri = URI.parse(url.to_s)
  return uri if %w[http https].include?(uri.scheme) && uri.host

  raise OptionParser::InvalidOption, "invalid url: #{url}"
end

def validate_language_code(code)
  unless code.is_a?(String) && code =~ /\A[A-Za-z]{2}\z/i
    raise OptionParser::InvalidOption, "invalid location: #{code.inspect}"
  end

  code.downcase
end

# ------------------------------------------------------------------------------
# Entry Point & Main Workflow
# ------------------------------------------------------------------------------

def main(json_arg)
  if json_arg.to_s.strip.empty?
    warn 'Error: Missing JSON argument.'
    exit 1
  end

  options = process_json_argument(JSON.parse(json_arg))
  update_ini_with_options(options)
end

main(ARGV[0])
