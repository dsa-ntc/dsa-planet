# frozen_string_literal: true

require 'faraday'
require 'faraday/follow_redirects'
require 'iniparser'
require 'nokogiri'
require 'uri'

INI_FILE = 'planet.ini'
AV_DIR = 'hackergotchi'

def initialize_faraday
  Faraday.new do |f|
    f.response :follow_redirects
    f.adapter :net_http
  end
end

def check_avatar(avatar, av_dir, faraday)
  if not avatar
    print "_ "
    return false
  end
  if avatar.include? '//'
    return check_url(avatar, faraday)
  else
    unless File.file?("#{av_dir}/#{avatar}")
      puts "✗\nAvatar not found: hackergotchi/#{avatar}"
      return true
    end
  end

  print '✓ '

  false
end

def check_url(url, faraday)
  res = faraday.get(URI(url))

  error = "✗\nNon successful status code #{res.status} when trying to access `#{url}`"

  if res.status.to_i.between?(300, 399) && res.headers.key?('location')
    puts "#{error}\nTry using `#{res.headers['location']}` instead"
    return true
  end

  unless res.status.to_i == 200
    puts error
    return true
  end

  print '✓ '

  false
end

def check_urls(url_arr, faraday)
  url_arr.any? { |url| check_url(url, faraday) }
end

def parse_xml(feed, faraday)
  xml = faraday.get(URI(feed)).body
  xml_err = Nokogiri::XML(xml).errors

  unless xml_err.empty?
    puts "✗\nUnusable XML syntax: #{feed}\n#{xml_err}"
    return true
  end

  puts '✓ '

  false
end

def check_unused_files(av_dir, avatars)
  hackergotchis = Dir.foreach(av_dir).select { |f| File.file?("#{av_dir}/#{f}") }
  diff = (hackergotchis - avatars)

  unless diff.empty?
    puts "There are unused files in hackergotchis:\n#{diff.join(', ')}"
    return true
  end

  false
end

def main
  faraday = initialize_faraday()
  planet_srcs = INI.load_file(INI_FILE)

  did_fail = false
  avatars = []

  planet_srcs.each do |key, section|
    next unless section.is_a?(Hash)

    avatar = section['avatar'] if section.key?('avatar')
    avatars << avatar

    print ":: #{key} =>  "
    did_fail = check_avatar(avatar, AV_DIR, faraday)

    link = section['link'] if section.key?('link')
    feed = section['feed'] if section.key?('feed')
    url_arr = [link, feed]
    did_fail = check_urls(url_arr, faraday) || did_fail
    did_fail = parse_xml(feed, faraday) || did_fail
  end

  did_fail = check_unused_files(AV_DIR, avatars) || did_fail
  if did_fail
    abort
  end
end

main()