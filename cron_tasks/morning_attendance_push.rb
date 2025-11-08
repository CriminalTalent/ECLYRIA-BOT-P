# ============================================
# cron_tasks/morning_attendance_push.rb
# ============================================
require_relative '../utils/professor_control'
require_relative '../utils/weather_message'

MORNING_ATTENDANCE_MESSAGES = [
  "좋은 아침이에요. 오늘도 출석으로 하루를 시작해보아요.",
  "일찍 일어났군요. 출석부터 하고 아침 먹어요.",
  "아침 해가 참 밝네요. 출석하고 좋은 하루 보내요.",
  "오늘도 건강하게 일어났군요. 출석 먼저 해요.",
  "교수가 출석부를 펼쳤어요. 이름 남기고 가요.",
  "아침 공기가 상쾌하군요. 출석하고 깊게 숨 쉬어봐요.",
  "일찍 일어나니 기분이 좋지요? 출석도 챙기고요.",
  "새로운 하루예요. 출석으로 좋은 시작 해봐요.",
  "잠은 잘 잤나요? 출석하고 아침 먹어요.",
  "오늘은 어떤 일들이 기다리고 있을까요? 출석부터 해요.",
  "교수가 기다리고 있었어요. 출석하러 오세요.",
  "아침은 먹었나요? 출석도 잊지 말고요.",
  "오늘도 학생들이 건강하길 바라요. 출석 먼저 하세요.",
  "날씨가 참 좋군요. 출석하고 산책이라도 하세요.",
  "교수 출석부에 이름 하나씩 적히는 게 참 기쁘네요.",
  "아침 일찍 일어나니 기특하군요. 출석하세요.",
  "오늘 하루도 건강하게 보내요. 출석부터 시작이에요.",
  "기숙사에서 잘 잤나요? 출석하고 수업 가요.",
  "교수도 아침 일찍 일어났어요. 같이 출석해봐요.",
  "오늘도 무사히 아침을 맞았군요. 출석으로 감사해요.",
  "아침 식사 전에 출석 먼저 하는 게 좋아요.",
  "교수가 창문을 열어놨어요. 출석하러 오세요.",
  "오늘도 학생들 얼굴 보니 교수가 행복하네요.",
  "출석은 하루의 첫 인사예요. 잊지 마세요.",
  "일찍 일어난 새가 먹이를 잡아요. 출석하세요.",
  "오늘도 즐거운 하루 되길 바라요. 출석부터 해봐요.",
  "교수 차 한 잔 준비했어요. 출석하고 마셔요.",
  "아침 햇살이 따뜻하군요. 출석하고 햇볕 쬐세요.",
  "건강이 제일이에요. 출석하고 아침 꼭 먹어요.",
  "오늘도 학생들 덕분에 교수가 즐겁네요. 출석하세요."
]

def run_morning_attendance_push(sheet_manager, mastodon_client)
  # ✅ 모듈 명시적 호출
  unless ProfessorControl.auto_push_enabled?(sheet_manager, "아침출석자동툿")
    puts "[스킵] 아침 출석 자동툿이 OFF 상태입니다."
    return
  end

  # ✅ 날씨 메시지 가져오기
  weather_info = WeatherMessage.random_weather_message_with_style
  attendance_msg = MORNING_ATTENDANCE_MESSAGES.sample

  # ✅ 날씨 + 출석 메시지 조합
  final_message = "#{weather_info[:text]}\n\n#{attendance_msg}"

  puts "[DEBUG] 전송할 메시지: #{final_message}"
  mastodon_client.broadcast(final_message)
end
