const fallbackReleaseUrl = 'https://github.com/benmkramer/ScreenshotMaxxing/releases/latest';

const formatDate = (value) => {
  if (!value) return '';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '';
  return new Intl.DateTimeFormat('en', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  }).format(date);
};

const setText = (id, value) => {
  const element = document.getElementById(id);
  if (element && value) element.textContent = value;
};

const setDownloadHref = (url) => {
  for (const id of ['download-link', 'download-link-secondary']) {
    const link = document.getElementById(id);
    if (link) link.href = url || fallbackReleaseUrl;
  }
};

const renderRelease = (release) => {
  if (!release || typeof release !== 'object') return;

  const releaseUrl = release.url || fallbackReleaseUrl;
  const downloadUrl = release.downloadUrl || releaseUrl;
  const date = formatDate(release.publishedAt);
  const version = release.tagName || release.name || 'Latest release';
  const assetName = release.assetName ? ` (${release.assetName})` : '';
  const published = date ? ` published ${date}` : '';

  setDownloadHref(downloadUrl);
  setText('release-summary', `${version}${published}${assetName}.`);
  setText('release-details', `Latest release: ${version}${published}. The primary download link points to ${release.assetName || 'the latest release asset'}.`);

  const digest = document.getElementById('release-digest');
  if (digest && release.digest) {
    digest.hidden = false;
    digest.textContent = release.digest;
  }
};

const loadRelease = async () => {
  try {
    const response = await fetch('release.json', {
      cache: 'no-store',
      headers: { Accept: 'application/json' },
    });
    if (!response.ok) return;
    renderRelease(await response.json());
  } catch {
    setDownloadHref(fallbackReleaseUrl);
  }
};

loadRelease();
