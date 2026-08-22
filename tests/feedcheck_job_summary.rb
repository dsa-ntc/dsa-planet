# frozen_string_literal: true

def image_warning_markdown(error_hash)
  [
    "\n## Unused Images\n",
    "\nThere are also unused avatar files in #{error_hash[:dir]}:\n",
    "\n* #{error_hash[:files].join("\n* ")}\n"
  ]
end

def prepare_message_markdown(error_hash)
  [
    "\n### #{error_hash[:key]}\n",
    "\n#{error_hash[:details]}\n"
  ]
end

def create_job_summary(error_messages)
  job_summary = ["# Feed Validity Summary\n\n## Feeds\n"]

  error_messages.each do |error|
    if error[:type] == :unused_files
      job_summary.concat image_warning_markdown(error)
    else
      job_summary.concat prepare_message_markdown(error)
    end
  end

  File.open('error-summary.md', 'w') { |file| file.write job_summary.join }
end
