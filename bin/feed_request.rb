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

def validate_url(url)
  uri = URI.parse(url.to_s)
  return uri if %w[http https].include?(uri.scheme) && uri.host

  raise OptionParser::InvalidOption, "invalid url: #{url}"
end

def validate_language_code(code)
  raise OptionParser::InvalidOption, "invalid location: #{code.inspect}" unless code.is_a?(String) && code =~ /\A[A-Za-z]{2}\z/i

  code.downcase
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
    if ini.has_section?('global')
      file.puts '[global]'
      ini['global'].each do |key, value|
        file.puts "#{key} = #{value}"
      end
      file.puts ''
    end
    file.write sorted_ini.to_s
  end
end

def sanitize_svg(uri, filename)
  extension = File.extname(filename)&.downcase
  return unless extension == '.svg'

  svg_data = File.read(filename)
  sanitized_svg = Loofah.scrub_fragment(svg_data, :prune).to_s
  File.open(filename, 'w') { |file| file.write(sanitized_svg) }
end

def convert_and_save_other_images(uri, base_filename, filename)
  extension = File.extname(filename)&.downcase
  return filename unless extension != '.svg'

  image = MiniMagick::Image.new(filename)

  # remove excess background
  image.fuzz '5%'
  image.trim

  # convert to square
  max_side = [image.width, image.height].max
  image.combine_options do |c|
    c.gravity 'center'
    c.background 'transparent'
    c.extent "#{max_side}x#{max_side}"
  end

  image.format 'webp'
  filename = "#{base_filename}.webp"
  image.write(filename)

  filename
end

def prepare_image(uri, base_filename)
  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
    response = http.get(uri.path.empty? ? '/' : uri.path)

    extension = File.extname(uri.path)&.downcase

    # Fallback to content-type if the URL lacks an explicit extension
    if extension.nil? || extension.empty?
      content_type = response['Content-Type']
      ext_map = { 'image/jpeg' => '.jpg', 'image/png' => '.png', 'image/webp' => '.webp', 'image/svg+xml' => '.svg' }
      extension = ext_map[content_type] || ''
    end

    filename = "#{base_filename}#{extension}"

    File.open(filename, 'wb') { |file| file.write(response.body) }

    filename
  end
end

def download_and_convert_image(options)
  avatar_input = options['avatar'].to_s.strip
  return nil if avatar_input.empty?

  avatar_url = validate_url(avatar_input)
  uri = URI(avatar_url)

  # Strip all non-alphanumeric characters to prevent path traversal
  safe_name = options['dsa-body'].to_s.downcase.gsub(/[^a-z0-9]/, '')
  base_filename = "#{AV_DIR}/#{safe_name}"

  filename = prepare_image(uri, base_filename)
  filename = convert_and_save_other_images(uri, base_filename, filename)
  sanitize_svg(uri, filename)

  File.basename(filename)
end

def process_json_argument(options)
  title = options['dsa-body']
  feed = validate_url(options['rss-feed'])
  link = validate_url(options['site'])
  avatar_url = download_and_convert_image(options)
  location = validate_language_code(options['language'])

  {
    title: title,
    feed: feed,
    link: link,
    avatar: avatar_url,
    location: location
  }
end

def main(json_arg)
  if json_arg.nil? || json_arg.strip.empty?
    warn "Error: Missing JSON argument."
    exit 1
  end

  options = process_json_argument(JSON.parse(json_arg))

  ini = IniFile.load(INI_FILE) || IniFile.new(encoding: 'UTF-8')
  section_name = options[:title].downcase.gsub(/[^a-z0-9]/, '')

  ini[section_name] = get_content(options[:title], options[:feed], options[:link], options[:avatar], options[:location])

  write_ini(ini)
end

main(ARGV[0])
