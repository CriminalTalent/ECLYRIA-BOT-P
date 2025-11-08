# ============================================
# /root/mastodon_bots/professor_bot/commands/enroll_command.rb
# ============================================
require 'date'

class EnrollCommand
  INITIAL_GALLEON = 20

  def initialize(sheet_manager, mastodon_client, sender, name, status)
    @sheet_manager = sheet_manager
    @mastodon_client = mastodon_client
    @sender = sender.gsub('@', '')
    @name = name
    @status = status
  end

  def execute
    existing_user = @sheet_manager.find_user(@sender)
    if existing_user
      @mastodon_client.reply(@status, "음, #{@name} 학생은 이미 입학한 상태로 보이네요. 다시 등록하지 않아도 됩니다.")
      return
    end

    # === 1️⃣ 사용자 탭 등록 ===
    user_row = [
      @sender,          # A: 사용자 ID
      @name,            # B: 이름
      INITIAL_GALLEON,  # C: 초기 갈레온
      "", "", ""        # D~F: 비워둠
    ]
    @sheet_manager.append_values("사용자!A:F", [user_row])
    puts "[입학] 사용자 등록 완료: #{@sender} (#{@name})"

    # === 2️⃣ 스탯 탭 등록 (간소화: HP / 민첩 / 행운 / 공격 / 방어) ===
    stat_row = [
      @sender,  # A: ID
      @name,    # B: 이름
      100,      # C: HP
      5,        # D: 민첩
      5,        # E: 행운
      5,        # F: 공격
      5         # G: 방어
    ]
    @sheet_manager.append_values("스탯!A:G", [stat_row])
    puts "[입학] 스탯(HP/민첩/행운/공격/방어) 등록 완료: #{@sender}"

    # === 3️⃣ 조사상태 탭 등록 ===
    investigate_row = [
      @sender,   # A: 사용자 ID
      "없음",    # B: 조사상태
      "-",       # C: 위치
      "0",       # D: 이동포인트
      "0",       # E: 은밀도
      "-"        # F: 협력상태
    ]
    @sheet_manager.append_values("조사상태!A:F", [investigate_row])
    puts "[입학] 조사상태 탭에 초기값 추가: #{@sender}"

    # === 4️⃣ 교수님식 입학 환영 메시지 ===
    welcome_message = <<~MSG
      #{@name} 학생, 호그와트에 온 걸 진심으로 환영합니다.
      새로운 배움의 여정이 이제 막 시작되었군요. 환영의 인사로 20갈레온을 드립니다.
    MSG

    @mastodon_client.reply(@status, welcome_message.strip, visibility: 'public')

  rescue => e
    puts "[에러] 입학 처리 중 오류: #{e.message}"
    puts e.backtrace.first(5)
    @mastodon_client.reply(@status, "음... 입학 처리 중 문제가 생긴 것 같아요. 잠시 후 다시 시도해보세요.", visibility: 'direct')
  end
end
