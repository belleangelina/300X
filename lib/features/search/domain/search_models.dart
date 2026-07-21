import 'package:x300/features/library/domain/library_models.dart';

class ForumSearchForm
{
    const ForumSearchForm({
        required this.actionUri,
        required this.formHash,
    });

    final Uri actionUri;
    final String formHash;
}

class ForumSearchPage
{
    const ForumSearchPage({
        required this.kind,
        required this.keyword,
        required this.searchId,
        required this.sourceThreads,
        required this.currentPage,
        required this.totalPages,
        this.nextPageUri,
    });

    final LibraryKind kind;
    final String keyword;
    final String searchId;
    final List<SourceThread> sourceThreads;
    final int currentPage;
    final int totalPages;
    final Uri? nextPageUri;

    bool get hasMore => nextPageUri != null;
}
