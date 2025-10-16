# professor_command_parser.rb
require_relative 'commands/enroll_command'
require_relative 'commands/attendance_command'
require_relative 'commands/homework_command'

module ProfessorParser
  def self.parse(mastodon, sheet_manager, mention)
    text = mention.status.content.gsub(/<[^>]*>/, '').strip
    sender_full = mention.account.acct
    
    # sender ID 정규화 - 다른 서버 호환성을 위해 도메인 부분 제거
    # 예: "Store@fortunaefons.masto.host" → "Store"
    # 예: "professor@eclyria.pics" → "professor"
    sender = sender_full.split('@').first
    
    puts "[교수봇] 처리 중: #{text} (from @#{sender_full} -> #{sender})"
    
    # 명령어 라우팅
    case text
    when /\[입학\/(.+?)\]/
      name = $1.strip
      EnrollCommand.new(sheet_manager, mastodon, sender, name).execute
    when /\[출석\]/
      AttendanceCommand.new(sheet_manager, mastodon, sender).execute
    when /\[과제\]/
      HomeworkCommand.new(sheet_manager, mastodon, sender).execute
    when /\[주머니\]/
      # 주머니 명령어가 있다면 처리
      PouchCommand.new(sheet_manager, mastodon, sender).execute if defined?(PouchCommand)
    else
      puts "[무시] 인식되지 않은 명령어: #{text}"
    end
  end
end
