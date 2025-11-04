# commands/enroll_command.rb
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
      @mastodon_client.reply(@status, "#{@name} 학생은 이미 입학한 상태입니다.")
      return
    end

    # === 1️⃣ 사용자 탭 등록 ===
    user_row = [
      @sender,     # A: 사용자 ID
      @name,       # B: 이름
      INITIAL_GALLEON, # C: 초기 갈레온
      "", "", ""   # 나머지 열은 비워둠
    ]
    @sheet_manager.append_values("사용자!A:F", [user_row])
    puts "[입학] 사용자 등록 완료: #{@sender} (#{@name})"

    # === 2️⃣ 스탯 탭 등록 ===
    stat_row = [
      @sender,     # A: ID
      @name,       # B: 이름
      1,           # C: 레벨 or 학년
      5,           # D: 행운
      5,           # E: 민첩
      5,           # F: 지능
      5,           # G: 매력
      5,           # H: 의지
      100          # I: HP (기본)
    ]
    @sheet_manager.append_values("스탯!A:I", [stat_row])
    puts "[입학] 스탯 초기값 등록 완료: #{@sender}"

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

    # === 4️⃣ 입학 환영 메시지 ===
    @mastodon_client.reply(
      @status,
      "#{@name} 학생, 호그와트에 온 걸 환영해요.\n" \
            visibility: 'public'
    )
  rescue => e
    puts "[에러] 입학 처리 중 오류: #{e.message}"
    puts e.backtrace.first(5)
    @mastodon_client.reply(@status, "입학 처리 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.", visibility: 'direct')
  end
end
