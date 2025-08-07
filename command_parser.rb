# professor_command_parser.rb
require_relative 'commands/enroll_command'
require_relative 'commands/attendance_command'
require_relative 'commands/homework_command'

module ProfessorParser
  def self.parse(mastodon, sheet_manager, mention)
    text = mention.status.content.gsub(/<[^>]*>/, '').strip
    sender = mention.account.acct
    puts "[교수봇] 처리 중: #{text}"

    # 명령어 라우팅
    case text
    when /\[입학\/(.+?)\]/
      name = $1.strip
      EnrollCommand.new(sheet_manager, mastodon, sender, name).execute
    when /\[출석\]/
      AttendanceCommand.new(sheet_manager, mastodon, sender).execute
    when /\[과제\]/
      HomeworkCommand.new(sheet_manager, mastodon, sender).execute
    end
  end
end
