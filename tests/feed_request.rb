# frozen_string_literal: true

require 'optparse'
require 'inifile'
require 'uri'

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

def assign_option(parser, option_hash, option_key)
  parser.on("-#{option_key[0]}", "--#{option_key} URL", "#{option_key.capitalize} URL") do |url|
    validate_url(url)
    option_hash[option_key.to_sym] = url
  end
end

def generate_op(option_hash)
  OptionParser.new do |parser|
    parser.banner = 'Usage: feed-request.rb [options]'
    parser.on('-t', '--title TITLE', 'Blog title') { |title| option_hash[:title] = title }
    %w[feed link avatar].each { |option_key| assign_option(parser, option_hash, option_key) }
    parser.on('-c', '--location LOCATION', 'Location') do |location|
      option_hash[:location] = validate_language_code(location)
    end
  end.parse!
end

def parse_options
  options = {}
  generate_op(options)
  options.compact!
  raise OptionParser::MissingArgument if %i[title feed link avatar].any? { |k| options[k].nil? }

  options
end

def main
  options = parse_options
  section_name = options[:title].downcase.tr(' ', '_')
  ini = IniFile.load('planet.ini')
  ini[section_name] = get_content(options[:title], options[:feed], options[:link], options[:avatar], options[:location])
  write_ini(ini)
end

main
