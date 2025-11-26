# ============================================
# cron_tasks/morning_attendance_push.rb
# 매일 다른 질문으로 출석 독려 (40개 질문 순환)
# ============================================
require_relative '../utils/professor_control'
require 'date'

# 40개의 질문 리스트
ATTENDANCE_QUESTIONS = [
  "Q. 친구는 얼이 사귀었나요?",
  "Q. 오늘은 어떤 수업이 기대되나요?",
  "Q. 가장 좋아하는 마법 과목은 무엇인가요?",
  "Q. 최근에 읽은 마법서 중 추천할 만한 것이 있나요?",
  "Q. 호그와트에서 가장 신비로운 장소는 어디라고 생각하나요?",
  "Q. 만약 애니마구스가 될 수 있다면 어떤 동물이 되고 싶나요?",
  "Q. 가장 배우고 싶은 마법 주문은 무엇인가요?",
  "Q. 금지된 숲에 가본 적이 있나요?",
  "Q. 퀴디치 경기는 좋아하시나요?",
  "Q. 어느 기숙사가 이번 학기 우승할 것 같나요?",
  "Q. 요즘 도서관에서 무엇을 공부하고 계신가요?",
  "Q. 가장 기억에 남는 마법 실습은 무엇이었나요?",
  "Q. 호그스미드 주말에는 어디를 가장 자주 가시나요?",
  "Q. 좋아하는 버터비어 토핑이 있나요?",
  "Q. 최근에 새로 사귄 친구가 있나요?",
  "Q. 오늘 아침 식사는 무엇을 드셨나요?",
  "Q. 가장 좋아하는 유령은 누구인가요?",
  "Q. 밤에 배회하다 교수님에게 걸린 적 있나요?",
  "Q. 만약 시간을 되돌릴 수 있다면 언제로 가고 싶나요?",
  "Q. 가장 무서웠던 어둠의 마법 방어술 수업은?",
  "Q. 펫을 키우고 있나요? 어떤 동물인가요?",
  "Q. 마법 지팡이의 재질과 코어는 무엇인가요?",
  "Q. 요즘 학교 소문은 뭐가 있나요?",
  "Q. 졸업 후에는 어떤 직업을 갖고 싶나요?",
  "Q. 지난 주말에는 무엇을 하셨나요?",
  "Q. 요즘 기분은 어떠신가요?",
  "Q. 스트레스를 푸는 나만의 방법이 있나요?",
  "Q. 가장 좋아하는 계절은 언제인가요?",
  "Q. 오늘 날씨를 한 단어로 표현한다면?",
  "Q. 최근에 감동받았던 일이 있나요?",
  "Q. 지금 가장 하고 싶은 것은 무엇인가요?",
  "Q. 올해의 목표는 무엇인가요?",
  "Q. 요즘 즐겨 듣는 음악이 있나요?",
  "Q. 만약 하루 동안 투명인간이 될 수 있다면?",
  "Q. 가장 가보고 싶은 마법 세계의 장소는?"
]

def run_morning_attendance_push(sheet_manager, mastodon_client)
  # ✅ 교수 시트에서 ON/OFF 확인
  unless ProfessorControl.auto_push_enabled?(sheet_manager, "아침출석자동툿")
    puts "[스킵] 아침 출석 자동툿이 OFF 상태입니다."
    return
  end

  # ✅ 오늘의 질문 선택 (날짜 기반으로 순환)
  day_of_year = Date.today.yday  # 1~365(366)
  question_index = (day_of_year - 1) % ATTENDANCE_QUESTIONS.length
  today_question = ATTENDANCE_QUESTIONS[question_index]

  # ✅ 출석 안내 메시지 생성
  attendance_message = <<~MSG
    ∴ 금일 출석체크 돌입니다. 아래에 멘션을 달아주시면 2갈레온, 기숙사 점수 1점이 지급됩니다. [출석]을 대답 앞에 달아주세요. 22시까지 출석이 가능합니다.

    #{today_question}
  MSG

  puts "[DEBUG] 전송할 메시지:\n#{attendance_message}"
  
  begin
    mastodon_client.broadcast(attendance_message.strip)
    puts "[출석 안내] 전송 완료 (질문 #{question_index + 1}/#{ATTENDANCE_QUESTIONS.length})"
  rescue => e
    puts "[에러] 출석 안내 전송 실패: #{e.message}"
  end
end
