# News Sources

The `news-digest` mode currently pulls same-day headlines from these Google News RSS endpoints:

- Top stories:
  - https://news.google.com/rss?hl=en-US&gl=US&ceid=US:en
- World:
  - https://news.google.com/rss/headlines/section/topic/WORLD?hl=en-US&gl=US&ceid=US:en
- Business:
  - https://news.google.com/rss/headlines/section/topic/BUSINESS?hl=en-US&gl=US&ceid=US:en
- Technology:
  - https://news.google.com/rss/headlines/section/topic/TECHNOLOGY?hl=en-US&gl=US&ceid=US:en
- Science:
  - https://news.google.com/rss/headlines/section/topic/SCIENCE?hl=en-US&gl=US&ceid=US:en
- Entertainment:
  - https://news.google.com/rss/headlines/section/topic/ENTERTAINMENT?hl=en-US&gl=US&ceid=US:en
- Sports:
  - https://news.google.com/rss/headlines/section/topic/SPORTS?hl=en-US&gl=US&ceid=US:en

Notes:

- Headlines are deduplicated by title.
- Selection is source-diverse (caps repeated publishers where possible).
- Ranking is "fun-first": science/tech/culture/sports are boosted.
- Headlines with graphic violence/disaster language are strongly down-ranked.
- The summary is a thematic synthesis, not a claim about every story.
