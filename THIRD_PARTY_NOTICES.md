# External dependencies and license scope

The MIT license applies to rights-cleared first-party scorer material. It does
not replace third-party terms or establish clearance of embedded method material.
Exact-candidate content and publication review remain separate owner decisions.
The public specifications retain their own license, notices and Candidate/Draft
statuses. No specification prose, model weights, gems or native tools are bundled.

`Gemfile.lock` pins the external Ruby dependencies and their RubyGems archive
checksums. Installed gem metadata declares the following licenses; users retain
the upstream licenses/notices supplied with their separately acquired copies.

| Dependency | Locked version | Declared license | Upstream |
| --- | --- | --- | --- |
| openai | 0.78.0 | Apache-2.0 | https://github.com/openai/openai-ruby |
| dotenv | 3.2.0 | MIT | https://github.com/bkeepers/dotenv |
| rexml | 3.4.4 | BSD-2-Clause | https://github.com/ruby/rexml |
| csv | 3.3.6 | Ruby or BSD-2-Clause | https://github.com/ruby/csv |
| base64 | 0.3.0 | Ruby or BSD-2-Clause | https://github.com/ruby/base64 |
| cgi | 0.5.2 | Ruby or BSD-2-Clause | https://github.com/ruby/cgi |
| connection_pool | 3.0.2 | MIT | https://github.com/mperham/connection_pool |
| drb | 2.2.3 | Ruby or BSD-2-Clause | https://github.com/ruby/drb |
| minitest | 6.0.6 | MIT | https://github.com/minitest/minitest |
| prism | 1.9.0 | MIT | https://github.com/ruby/prism |
| rake | 13.4.2 | MIT | https://github.com/ruby/rake |

Ruby, Bundler, zip and unzip are user-acquired tools with their own distribution
terms. Their executables and licenses are not copied into this distribution.
The package's numeric-source smoke test uses zip/unzip and an inert SDK-client
boundary to render requests; it never calls a model. Model acquisition, runtime
qualification and redistribution are outside this source package.

The four retained test-support text files enumerate benchmark IDs only, without
source prose, scores or run results. Historical profile code remains explicitly
loaded as described in `docs/CODE_STATUS.md`; retaining it does not qualify a
profile for a new source, method or public history identity.
