# bot/mastodon_client.rb
require 'mastodon'

module MastodonClient
  @last_mention_id = nil

  def self.client
    @client ||= Mastodon::REST::Client.new(
      base_url: ENV['MASTODON_BASE_URL'],
      bearer_token: ENV['MASTODON_TOKEN']
    )
  end

  def self.listen_mentions
    begin
      # 마지막으로 확인한 멘션 이후의 새로운 멘션만 가져오기
      options = {}
      options[:since_id] = @last_mention_id if @last_mention_id
      
      notifications = client.notifications(options)
      mentions = notifications.select { |n| n.type == 'mention' }
      
      # 새로운 멘션이 있다면 마지막 ID 업데이트
      if mentions.any?
        @last_mention_id = mentions.first.id
        puts "새로운 멘션 #{mentions.size}개 도착!"
        
        # 시간순으로 처리하기 위해 reverse
        mentions.reverse.each do |mention|
          acct = mention.account.acct
          content = mention.status.content.gsub(/<[^>]*>/, '').strip
          puts "   @#{acct}: #{content}"
          
          yield mention if block_given?
        end
      else
        print "."  # 조용한 대기 표시
      end
      
    rescue Mastodon::Error::TooManyRequests => e
      puts "API 요청 한도 초과, 60초 대기..."
      sleep 60
    rescue Mastodon::Error::Unauthorized => e
      puts "인증 오류: 토큰을 확인해주세요"
      puts "   #{e.message}"
      sleep 30
    rescue Mastodon::Error::NotFound => e
      puts "서버를 찾을 수 없습니다: BASE_URL을 확인해주세요"
      puts "   #{e.message}"
      sleep 30
    rescue => e
      puts "멘션 확인 중 오류: #{e.message}"
      puts "   #{e.class}: #{e.backtrace.first}"
      sleep 30
    end
  end

  def self.reply(mention, message)
    begin
      acct = mention.account.acct
      status_id = mention.status.id
      
      # 메시지가 길면 여러 툿으로 분할
      messages = split_long_message(message, acct)
      
      if messages.length == 1
        # 단일 메시지
        response = send_single_reply(acct, messages.first, status_id)
        puts "@#{acct}에게 응답 완료"
        response
      else
        # 다중 메시지 (스레드)
        responses = send_thread_replies(acct, messages, status_id)
        puts "@#{acct}에게 스레드 응답 완료 (#{messages.length}개 툿)"
        responses
      end
      
    rescue Mastodon::Error::TooManyRequests => e
      puts "답글 전송 API 한도 초과, 잠시 대기..."
      sleep 60
      retry
    rescue Mastodon::Error::UnprocessableEntity => e
      puts "답글 전송 실패 (중복 또는 형식 오류): #{e.message}"
      nil
    rescue => e
      puts "답글 전송 중 오류: #{e.message}"
      puts "   대상: @#{acct rescue 'unknown'}"
      puts "   메시지 길이: #{message.length rescue 0}자"
      nil
    end
  end

  private

  def self.split_long_message(message, acct)
    mention_prefix = "@#{acct} "
    max_length = 500
    available_length = max_length - mention_prefix.length
    
    # 메시지가 충분히 짧으면 그대로 반환
    if message.length <= available_length
      return [message]
    end
    
    puts "긴 메시지를 분할합니다 (#{message.length}자 → 여러 툿)"
    
    messages = []
    remaining = message.dup
    part_number = 1
    
    while remaining.length > 0
      if remaining.length <= available_length
        # 마지막 부분
        messages << remaining
        break
      end
      
      # 자연스러운 분할점 찾기
      cut_point = find_good_cut_point(remaining, available_length - 10) # 여유공간 확보
      
      if cut_point > 0
        part = remaining[0...cut_point].strip
        remaining = remaining[cut_point..-1].strip
      else
        # 적절한 분할점을 못 찾으면 강제로 자르기
        part = remaining[0...(available_length - 10)]
        remaining = remaining[(available_length - 10)..-1]
      end
      
      # 연속 표시 추가 (첫 번째 툿 제외)
      if part_number > 1
        part = "#{part}"
      end
      
      messages << part
      part_number += 1
    end
    
    # 각 메시지에 부분 표시 추가 (2개 이상일 때만)
    if messages.length > 1
      messages = messages.map.with_index do |msg, idx|
        "#{msg}\n\n(#{idx + 1}/#{messages.length})"
      end
    end
    
    messages
  end

  def self.find_good_cut_point(text, max_length)
    return 0 if text.length <= max_length
    
    # 우선순위: 문단 > 문장 > 단어
    cut_candidates = [
      text.rindex("\n\n", max_length),  # 문단 구분
      text.rindex("\n", max_length),    # 줄바꿈
      text.rindex(". ", max_length),    # 문장 끝 (영어)
      text.rindex("! ", max_length),    # 느낌표
      text.rindex("? ", max_length),    # 물음표
      text.rindex("。", max_length),     # 일본어 문장 끝
      text.rindex(" ", max_length),     # 단어 구분
    ].compact.max
    
    cut_candidates || 0
  end

  def self.send_single_reply(acct, message, reply_to_id)
    client.create_status(
      "@#{acct} #{message}",
      in_reply_to_id: reply_to_id,
      visibility: 'public'
    )
  end

  def self.send_thread_replies(acct, messages, initial_reply_to_id)
    responses = []
    current_reply_to_id = initial_reply_to_id
    
    messages.each_with_index do |message, index|
      response = client.create_status(
        "@#{acct} #{message}",
        in_reply_to_id: current_reply_to_id,
        visibility: 'public'
      )
      
      responses << response
      current_reply_to_id = response.id  # 다음 툿은 이 툿에 대한 답글
      
      puts "   부분 #{index + 1}/#{messages.length} 전송 완료"
      
      # API 한도를 고려해 잠시 대기
      sleep 1 if index < messages.length - 1
    end
    
    responses
  end

  public

  def self.test_connection
    begin
      account = client.verify_credentials
      puts "마스토돈 서버 연결 성공!"
      puts "   계정: @#{account.acct}"
      puts "   표시명: #{account.display_name}"
      puts "   팔로워: #{account.followers_count}명"
      true
    rescue Mastodon::Error::Unauthorized => e
      puts "서버 연결 실패: 토큰이 유효하지 않습니다"
      puts "   #{e.message}"
      false
    rescue Mastodon::Error::NotFound => e
      puts "서버 연결 실패: 서버를 찾을 수 없습니다"
      puts "   BASE_URL: #{ENV['MASTODON_BASE_URL']}"
      puts "   #{e.message}"
      false
    rescue => e
      puts "서버 연결 실패: #{e.message}"
      puts "   #{e.class}"
      false
    end
  end

  def self.post_status(message, visibility: 'public')
    begin
      response = client.create_status(message, visibility: visibility)
      puts "상태 메시지 게시 완료"
      response
    rescue => e
      puts "상태 메시지 게시 실패: #{e.message}"
      nil
    end
  end

  # 디버깅용 메서드
  def self.get_recent_mentions(limit: 10)
    begin
      notifications = client.notifications(limit: limit)
      mentions = notifications.select { |n| n.type == 'mention' }
      
      puts "최근 멘션 #{mentions.size}개:"
      mentions.each_with_index do |mention, index|
        acct = mention.account.acct
        content = mention.status.content.gsub(/<[^>]*>/, '').strip
        created_at = mention.created_at
        puts "   #{index + 1}. @#{acct} (#{created_at}): #{content[0..50]}#{'...' if content.length > 50}"
      end
      
      mentions
    rescue => e
      puts "최근 멘션 조회 실패: #{e.message}"
      []
    end
  end
end
