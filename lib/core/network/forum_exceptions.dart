class ForumException implements Exception
{
    const ForumException(this.message);

    final String message;

    @override
    String toString()
    {
        return message;
    }
}

class ForumConnectionException extends ForumException
{
    const ForumConnectionException([
        super.message = '无法连接百合会论坛',
    ]);
}

class ForumSessionExpiredException extends ForumException
{
    const ForumSessionExpiredException() : super('登录状态已失效');
}

class ForumParseException extends ForumException
{
    const ForumParseException([
        super.message = '论坛页面结构无法识别',
    ]);
}
