class ReadingAnchor
{
    const ReadingAnchor._();

    static int positionForProgress(double progress, int maxPosition)
    {
        if (maxPosition <= 0)
        {
            return 0;
        }
        return (progress.clamp(0.0, 1.0) * maxPosition).round();
    }

    static double progressForPage(int page, int pageCount)
    {
        if (pageCount <= 1)
        {
            return 0;
        }
        return (page.clamp(0, pageCount - 1) / (pageCount - 1))
            .clamp(0.0, 1.0);
    }

    static int pageForProgress(double progress, int pageCount)
    {
        if (pageCount <= 1)
        {
            return 0;
        }
        return (progress.clamp(0.0, 1.0) * (pageCount - 1)).round();
    }
}
