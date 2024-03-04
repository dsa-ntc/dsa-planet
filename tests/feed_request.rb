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
  uri = URI.parse(url)
  return uri if %w[http https].include?(uri.scheme) && uri.host.include?('.')

  raise OptionParser::InvalidOption, "invalid url: #{url}"
end

def validate_language_code(code)
  raise OptionParser::InvalidOption, "invalid location: #{code}" unless code =~ /\A[A-Za-z]{2}\z/i

  code.downcase
end

def get_content(title, feed, link, avatar, location = nil)
  {
    'title' => title,
    'feed' => feed,
    'link' => link,
    'location' => location,
    'avatar' => avatar
  }.compact
end

def write_ini(ini, title)
  sorted_ini = IniFile.new(encoding: 'UTF-8')
  ini.each_section do |section|
    next if section == 'global'

    sorted_ini[section] = ini[section]
  end
  File.open(INI_FILE, 'w') do |file|
    file.puts "title = #{title}"
    file.puts ''
    file.write sorted_ini.to_s
  end
end

def sanitize_svg(uri, filename)
  extension = File.extname(uri.path)&.downcase
  return unless extension == '.svg'

  svg_data = File.read(filename)
  sanitized_svg = Loofah.scrub_fragment(svg_data, :prune).to_s
  File.open(filename, 'w') { |file| file.write(sanitized_svg) }
end

def convert_and_save_other_images(uri, base_filename, filename)
  extension = File.extname(uri.path)&.downcase
  return filename unless extension != '.svg'

  image = MiniMagick::Image.new(filename)
  image.format 'webp'
  filename = "#{base_filename}.webp"
  image.write(filename)

  filename
end

def prepare_image(uri, base_filename)
  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
    response = http.get(uri.path)

    extension = File.extname(uri.path)&.downcase
    filename = "#{base_filename}#{extension}"

    File.open(filename, 'wb') { |file| file.write(response.body) }

    filename
  end
end

def download_and_convert_image(options)
  avatar_url = validate_url(options['what_image_do_you_want_to_use'])
  uri = URI(avatar_url)
  base_filename = "#{AV_DIR}/#{options['enter_your_chapter_or_working_group_name'].downcase.tr('- ', '')}"

  filename = prepare_image(uri, base_filename)
  filename = convert_and_save_other_images(uri, base_filename, filename)
  sanitize_svg(uri, filename)

  File.basename(filename)
end

def process_json_argument(json_argument)
  title = json_argument['enter_your_chapter_or_working_group_name']
  feed = validate_url(json_argument['what_is_your_rss_feed'])
  link = validate_url(json_argument['what_is_your_website'])
  avatar_url = download_and_convert_image(json_argument)
  location = validate_language_code(json_argument['what_language_is_your_content_in'])

  {
    title: title,
    feed: feed,
    link: link,
    avatar: avatar_url,
    location: location
  }
end

def main(json_arg)
  options = process_json_argument(JSON.parse(json_arg))
  ini = IniFile.load(INI_FILE)
  section_name = options[:title].downcase.tr('- ', '')
  ini[section_name] = get_content(options[:title], options[:feed], options[:link], options[:avatar], options[:location])
  write_ini(ini, ini['global']['title'])
end

main(ARGV[0])
