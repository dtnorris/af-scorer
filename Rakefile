require "rake/testtask"

if ENV["BUILDKITE"] == "true"
  require "bundler"

  desc "Run the scorer suite with pinned public specifications in Buildkite"
  task :test do
    Bundler.with_unbundled_env do
      system({ "BUILDKITE" => nil }, "bash", ".buildkite/scorer-tests.sh", exception: true)
    end
  end
else
  Rake::TestTask.new do |t|
    t.libs << "lib"
    t.libs << "test"
    t.pattern = "test/**/*_test.rb"
    t.warning = false
  end
end

task default: :test
