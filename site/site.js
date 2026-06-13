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

const setHref = (id, url) => {
  const link = document.getElementById(id);
  if (link) link.href = url || fallbackReleaseUrl;
};

const setDownloadHref = (url) => {
  for (const id of ['download-link', 'download-link-secondary']) {
    setHref(id, url);
  }
};

const showDigest = (digest) => {
  const row = document.getElementById('release-digest-row');
  const value = document.getElementById('release-digest');
  if (!row || !value || !digest) return;

  row.hidden = false;
  value.textContent = digest;
};

const renderRelease = (release) => {
  if (!release || typeof release !== 'object') return;

  const releaseUrl = release.url || fallbackReleaseUrl;
  const downloadUrl = release.downloadUrl || releaseUrl;
  const date = formatDate(release.publishedAt);
  const version = release.tagName || release.name || 'Latest release';
  const assetName = release.assetName || 'Latest release asset';
  const published = date ? ` published ${date}` : '';

  setDownloadHref(downloadUrl);
  setHref('release-page-link', releaseUrl);
  setText('release-summary', `${version}${published}. Official builds are signed and notarized DMGs from this repository.`);
  setText('release-details', `The primary download link points to ${assetName}. Inspect the GitHub Release before installing if you want the full release context.`);
  setText('release-version', version);
  setText('release-date', date || 'Available on GitHub Releases');
  setText('release-asset', assetName);
  showDigest(release.digest);
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
