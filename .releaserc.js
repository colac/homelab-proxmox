module.exports = {
  branches: [
    'main',
    'master',
    {
      name: 'feature/**',
      prerelease: 'feature'
    },
    {
      name: 'fix/**',
      prerelease: 'fix'
    }
  ],
  tagFormat: 'v${version}',
  plugins: [
    '@semantic-release/commit-analyzer',
    '@semantic-release/release-notes-generator',
    '@semantic-release/changelog',
    // The colac.homelab collection's galaxy.yml carries a version field that
    // nothing else updates; without this, every install reports the version
    // of whichever release last edited it by hand. Consumers still select by
    // git tag — this only makes `ansible-galaxy collection list` tell the truth.
    [
      '@semantic-release/exec',
      {
        prepareCmd: "sed -i 's/^version: .*/version: ${nextRelease.version}/' ansible/galaxy.yml"
      }
    ],
    [
      '@semantic-release/git',
      {
        assets: ['CHANGELOG.md', 'ansible/galaxy.yml'],
        message: 'chore(release): ${nextRelease.version} [skip ci]\n\n${nextRelease.notes}'
      }
    ],
    '@semantic-release/github'
  ]
};
