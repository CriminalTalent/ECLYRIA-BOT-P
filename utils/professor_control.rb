# /root/mastodon_bots/professor_bot/utils/professor_control.rb
require 'date'

module ProfessorControl
  # 교수 시트에서 특정 기능이 켜져 있는지 확인
  def auto_push_enabled?(sheet_manager, feature_name)
    begin
      sheet = sheet_manager.get_sheet("교수")
      values = sheet_manager.get_values("교수!A1:Z2") || []
      return false if values.empty?

      headers = values[0]
      statuses = values[1] || []

      headers.each_with_index do |header, idx|
        next if header.nil?
        next unless header.strip == feature_name

        cell_value = statuses[idx]

        # ✅ 체크박스(true/false) + 문자열(ON/OFF) 모두 지원
        return true if cell_value == true
        return true if cell_value.to_s.strip.upcase == "ON"
        return false
      end

      false
    rescue => e
      puts "[에러] auto_push_enabled? 확인 중 오류: #{e.message}"
      false
    end
  end

  # 시간 범위 확인 유틸 (22시 이후 출석 제한 등)
  def within_time_range?(start_hour, end_hour)
    now = Time.now
    current_hour = now.hour
    (start_hour <= current_hour && current_hour < end_hour)
  end

  # 공지/멘트용 공통 포맷 생성
  def formatted_announcement(type, message)
    timestamp = Time.now.strftime("%H:%M")
    "[#{type}] #{timestamp} - #{message}"
  end
end
