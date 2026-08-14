import 'package:x300/features/forum/data/forum_origin_policy.dart';

class ForumWebViewPolicy
{
    const ForumWebViewPolicy({this.originPolicy = const ForumOriginPolicy()});

    final ForumOriginPolicy originPolicy;

    bool isAllowedNavigation(Uri uri)
    {
        if (!originPolicy.isAllowed(uri) || !_isRegisteredPath(uri.path))
        {
            return false;
        }
        final List<String> mobileValues = uri.queryParametersAll['mobile'] ??
                const <String>[];
        return mobileValues.isEmpty ||
                (mobileValues.length == 1 && mobileValues.single == '2');
    }

    bool isRegisteredInitialUri(Uri uri)
    {
        if (!isAllowedNavigation(uri))
        {
            return false;
        }
        final List<String> mobileValues = uri.queryParametersAll['mobile'] ??
                const <String>[];
        return mobileValues.length == 1 && mobileValues.single == '2';
    }

    void requireRegisteredInitialUri(Uri uri)
    {
        if (!isRegisteredInitialUri(uri))
        {
            throw const ForumActionSecurityException(
                '论坛原页入口不是已登记的百合会移动页面',
            );
        }
    }

    bool _isRegisteredPath(String path)
    {
        if (const <String>{
            '/',
            '/index.php',
            '/forum.php',
            '/home.php',
            '/member.php',
            '/search.php',
            '/misc.php',
            '/plugin.php',
        }.contains(path))
        {
            return true;
        }
        return RegExp(r'^/(?:thread|forum)-\d+(?:-\d+)*\.html$')
            .hasMatch(path);
    }
}
