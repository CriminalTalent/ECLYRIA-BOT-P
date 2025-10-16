# commands/enroll_command.rb
require 'date'

class EnrollCommand
  INITIAL_GALLEON = 20

  def initialize(sheet_manager, mastodon_client, sender, name)
    @sheet_manager = sheet_manager
    @mastodon_client = mastodon_client
    @sender = sender.gsub('@', '')  # @domain 제거
    @name = name
  end

  def execute
    # 기존 사용자 확인
    existing_user = @sheet_manager.find_user(@sender)
    
    if existing_user
      @mastodon_client.reply(@sender, "#{@name}님은 이미 입학하셨습니다.")
      return
    end

    # 1. 사용자 탭에 데이터 추가
    user_row = [
      @sender,        # A: ID
      @name,          # B: 이름
      INITIAL_GALLEON,# C: 갈레온
      "",             # D: 아이템
      "",             # E: 기숙사
      ""              # F: 메모
    ]
    
    @sheet_manager.append_values("사용자!A:F", [user_row])
    puts "[입학] 사용자 탭에 추가: #{@sender} (#{@name})"

    # 2. 스탯 탭에 ID와 이름만 추가 (스탯은 DM이 직접 입력)
    stat_row = [
      @sender,        # A: ID
      @name           # B: 이름
      # C~G: 체력, 공격력, 방어력, 민첩, 행운은 DM이 직접 입력
    ]
    
    @sheet_manager.append_values("스탯!A:B", [stat_row])
    puts "[입학] 스탯 탭에 ID/이름만 추가: #{@sender} (#{@name})"

    # 3. 응답 메시지
    @mastodon_client.reply(@sender, "#{@name}님, 입학을 환영합니다. 초기 갈레온 20을 지급하였습니다.")
  end
end
