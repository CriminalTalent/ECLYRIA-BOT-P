def random_weather_message_with_style
  weather_conditions = [
    { text: "오늘은 눈이 많이 오네요. 미끄럼 조심하세요.", style: :snow },
    { text: "기숙사 밖은 강풍이 붑니다. 외출은 가급적 삼가세요.", style: :wind },
    { text: "아침 안개가 자욱합니다. 이동 시 안전에 유의하세요.", style: :fog },
    { text: "기숙사 앞에 눈사람이 생겼어요. 누가 만든 걸까요?", style: :snowman }
  ]

  advice_pool = [
    "따뜻한 차 한 잔이 집중력을 높여줍니다.",
    "오늘은 책장 정리부터 시작해보는 건 어떨까요?",
    "점심 전까지 목표 하나를 마무리해보세요.",
    "창문을 열고 환기를 해보는 것도 좋아요.",
    "지금 이 순간의 집중이 내일을 바꿉니다.",
    "좋은 음악과 함께 공부해보세요.",
    "몸도 마음도 따뜻하게 챙겨주세요.",
    "혼자보다는 함께 공부하면 더 즐거워요.",
    "노트 정리는 복습의 시작입니다.",
    "오래된 할 일부터 처리해보세요.",
    "짧은 산책이 생각을 정리하는 데 도움이 됩니다.",
    "기숙사 주변 청소를 잠깐 해보는 것도 좋아요.",
    "정리된 책상은 마법처럼 집중력을 높입니다.",
    "오늘 하루도 포기하지 않고 도전해봅시다.",
    "작은 목표라도 하나씩 이뤄보세요.",
    "감기 조심하세요. 마법도 아플 수 있어요.",
    "무엇보다 중요한 건 건강입니다.",
    "따뜻한 메시지가 누군가에게 큰 위로가 될 수 있어요.",
    "좋은 하루는 좋은 마음가짐에서 시작됩니다.",
    "자신을 믿는 것이 최고의 마법입니다."
  ]

  selected_weather = weather_conditions.sample
  selected_advice = advice_pool.sample

  # 최종 메시지 구성
  final_message = "#{selected_weather[:text]} #{selected_advice} 출석하겠습니다."

  {
    text: final_message,
    style: selected_weather[:style]
  }
end
