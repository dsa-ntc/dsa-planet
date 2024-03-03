# frozen_string_literal: true

require 'optparse'
require 'inifile'
require 'uri'
require 'json'

def validate_url(url)
  uri = URI.parse(url)
  return if %w[http https].include?(uri.scheme) && uri.host.include?('.')

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

def write_ini(ini)
  sorted_ini = IniFile.new(encoding: 'UTF-8')
  ini.each_section do |section|
    next if section == 'global'

    sorted_ini[section] = ini[section]
  end
  sorted_ini.write(filename: 'planet.ini')
end

def parse_json_argument(json_argument)
  validate_url(json_argument['what_is_your_rss_feed'])
  validate_url(json_argument['what_is_your_website'])
  validate_url(json_argument['what_image_do_you_want_to_use'])
  {
    title: json_argument['enter_your_chapter_or_working_group_name'],
    feed: json_argument['what_is_your_rss_feed'],
    link: json_argument['what_is_your_website'],
    avatar: json_argument['what_image_do_you_want_to_use'],
    location: validate_language_code(json_argument['what_language_is_your_content_in'])
  }
end

def main(json_arg)
  json_argument = JSON.parse(json_arg)
  options = parse_json_argument(json_argument)
  section_name = options[:title].downcase.tr(' ', '_')
  ini = IniFile.load('planet.ini')
  ini[section_name] = get_content(options[:title], options[:feed], options[:link], options[:avatar], options[:location])
  write_ini(ini)
end

main(ARGV[0])
