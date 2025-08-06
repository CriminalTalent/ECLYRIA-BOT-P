# cron_tasks/evening_attendance_end.rb

require_relative '../professor_control'
require_relative '../push_notifier'

EVENING_ATTENDANCE_MESSAGES = [
  "곧 하루가 저물어 갑니다. 아직 출석하지 않으셨다면 서둘러 주세요.",
  "출석 마감 시간이 다가오고 있어요. 오늘도 기록을 남겨보는 건 어떨까요?",
  "조용한 밤입니다. 아직 출석하지 않은 분들 계신가요?",
  "출석 마감까지 얼마 남지 않았습니다. 하루를 마무리해볼 시간이에요.",
  "오늘 하루를 남기고 싶다면, 지금이 마지막 기회일지도 몰라요.",
  "아직 출석이 안 되어 있다면, 조용히 다녀가주세요.",
  "출석은 오늘을 기억하는 작은 의식입니다. 잊지 마세요.",
  "곧 출석 마감입니다. 조용히, 천천히, 잊지 말고요.",
  "교수진은 출석을 확인하고 오늘을 마무리하려 합니다.",
  "늦은 밤, 출석을 통해 스스로에게 하루를 칭찬해 보세요.",
  "출석 마감 시간입니다. 아직이시라면 지금이 마지막 기회예요.",
  "기숙사 복도 시계가 열 시를 가리키고 있네요. 출석 마감입니다.",
  "아직 출석하지 않은 분은 계신가요? 조용히 다녀가셔도 괜찮습니다.",
  "오늘 하루를 잊지 않기 위해 출석으로 마무리해봅시다.",
  "곧 출석 마법이 잠들게 됩니다. 그 전에 다녀가세요.",
  "교수님들도 하루를 마무리하며 출석부를 닫고자 합니다.",
  "출석을 잊은 날도 괜찮지만, 남길 수 있다면 더 좋겠죠.",
  "오늘도 고생 많으셨습니다. 마지막으로 출석을 잊지 마세요.",
  "출석 마감 시간이 가까워졌습니다. 혹시 잊고 계셨다면 지금이 기회입니다.",
  "출석 마감 알림입니다. 늦기 전에 오늘을 남겨주세요."
]

def run_evening_attendance_end(sheet_manager, mastodon_client)
  unless auto_push_enabled?(sheet_manager, "저녁 출석 마감 자동툿")
    puts "[스킵] 저녁 출석 마감 자동툿이 OFF 상태입니다."
    return
  end

  message = EVENING_ATTENDANCE_MESSAGES.sample
  PushNotifier.broadcast(mastodon_client, message)
end

