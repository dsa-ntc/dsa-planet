# frozen_string_literal: true

def image_warning_markdown(messages)
  unused_images = messages.last.match('There are unused files in [A-Za-z]+: (.*)')[1].split(',').join("\n*")
  ["\n## Unused Images\n", "\nThere are also unused avatar files:\n\n* #{unused_images}\n"]
end

def prepare_message_markdown(message)
  header, body = message.split('=>').map(&:strip)
  return unless header && body

  ["\n### #{header.gsub(/^:: /, '')}\n", "\n#{body}\n"]
end

def create_job_summary(error_messages)
  job_summary = error_messages.map do |message|
    prepare_message_markdown(message)
  end.compact.unshift "# Feed Validity Summary\n\n## Feeds\n"
  job_summary.concat image_warning_markdown(error_messages) if error_messages.last.include? 'There are unused files in'
  File.open('error-summary.md', 'w') { |file| file.write job_summary.join }
end
