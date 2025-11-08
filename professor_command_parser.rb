# /root/mastodon_bots/professor_bot/professor_command_parser.rb
require_relative 'commands/enroll_command'
require_relative 'commands/attendance_command'
require_relative 'commands/homework_command'

module ProfessorParser
  def self.parse(sheet_manager, mastodon, mention)
    # HTML 태그 제거
    text = mention['status']['content'].gsub(/<[^>]*>/, '').strip
    sender_full = mention['account']['acct']
    sender = sender_full.split('@').first

    puts "[교수봇] 처리 중: #{text} (from @#{sender_full})"

    case text
    when /\[입학\/(.+?)\]/  # [입학/이름]
      name = $1.strip
      EnrollCommand.new(sheet_manager, mastodon, sender, name, mention['status']).execute

    when /\[출석\]/
      AttendanceCommand.new(sheet_manager, mastodon, sender, mention['status']).execute

    when /\[과제\]/
      HomeworkCommand.new(sheet_manager, mastodon, sender, mention['status']).execute

    else
      puts "[무시] 인식되지 않은 명령어: #{text}"
    end
  rescue => e
    puts "[에러] 명령어 파싱 실패: #{e.message}"
  end
end
