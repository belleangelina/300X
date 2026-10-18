class ForumException implements Exception {
  const ForumException(this.message);

  final String message;

  @override
  String toString() {
    return message;
  }
}

class ForumConnectionException extends ForumException {
  const ForumConnectionException([super.message = '无法连接百合会论坛']);
}

/// 连接失败或超时，请求没有得到论坛响应；启动校验可按离线处理。
class ForumUnreachableException extends ForumConnectionException {
  const ForumUnreachableException([super.message = '无法连接百合会论坛']);
}

class ForumSessionExpiredException extends ForumException {
  const ForumSessionExpiredException() : super('登录状态已失效');
}

class ForumParseException extends ForumException {
  const ForumParseException([super.message = '论坛页面结构无法识别']);
}
