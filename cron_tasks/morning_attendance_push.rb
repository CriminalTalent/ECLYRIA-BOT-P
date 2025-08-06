# cron_tasks/morning_attendance_push.rb

require_relative '../professor_control'
require_relative '../push_notifier'
require_relative '../utils/weather_message'  # 날씨 메시지 제공 함수 포함

MORNING_ATTENDANCE_MESSAGES = [
  "좋은 아침입니다. 오늘도 출석으로 하루를 시작해볼까요?",
  "하루의 시작은 가볍게 인사하는 것부터입니다. 출석해주세요.",
  "햇살이 비치네요. 기지개 켜고, 출석도 잊지 마세요.",
  "기숙사 복도에서 아침 인사가 들려옵니다. 지금쯤 출석하실 시간이에요.",
  "오늘도 함께 하루를 시작합시다. 출석은 작은 약속이에요.",
  "마법 수업 전, 출석 체크 먼저 해주세요.",
  "마음도 몸도 가볍게, 출석으로 하루를 시작해보세요.",
  "출석은 오늘 하루를 준비하는 작지만 중요한 시작이에요.",
  "기분 좋은 하루가 되려면 출석도 챙겨야겠죠?",
  "일찍 일어난 만큼 보람도 가득한 하루가 될 거예요. 출석하시겠어요?",
  "교수님도 출석부를 펼쳤답니다. 이름을 남겨주세요.",
  "오늘은 어떤 일이 펼쳐질까요? 먼저 출석하고 시작해요.",
  "마법 같은 하루를 위해, 출석이라는 주문부터 외워볼까요?",
  "기숙사 생활은 출석부터 차곡차곡 쌓여간답니다.",
  "살랑이는 바람과 함께 이름도 남겨주세요.",
  "새로운 하루, 새로운 기회. 오늘 하루도 시작해봅시다.",
  "오늘도 여러분의 하루를 응원합니다. 준비되셨나요?",
  "출석은 하루를 여는 열쇠랍니다. 문을 열어보세요.",
  "기숙사 공지판에 오늘의 이름들이 하나둘 모이고 있어요.",
  "좋은 하루는 한 발 먼저 나아가는 것에서 시작됩니다."
]

def run_morning_attendance_push(sheet_manager, mastodon_client)
  unless auto_push_enabled?(sheet_manager, "아침 출석 자동툿")
    puts "[스킵] 아침 출석 자동툿이 OFF 상태입니다."
    return
  end

  weather_info = random_weather_message_with_style # { text: "...", style: :tag }
  attendance_msg = MORNING_ATTENDANCE_MESSAGES.sample

  final_message = "#{weather_info[:text]}\n\n#{attendance_msg}"

  PushNotifier.broadcast(mastodon_client, final_message)
end

