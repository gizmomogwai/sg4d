def examples
  [
    {
      name: "hello-world-camera",
      path: "examples/hello-world",
      arguments: ["camera"],
    },
    {
      name: "hello-world-parallel",
      path: "examples/hello-world",
      arguments: ["parallel"],
    },
    {
      name: "viewed",
      path: "examples/viewed",
      arguments: ["--directory=."],
    },
  ]
end

def configs
  ["opengl2", "opengl33"]
end

desc "Run all"
task "run-all"

desc "Build all"
task "build-all"

examples.each do |i|
  configs.each do |config|
    name = "run-#{i[:name]}-#{config}"
    desc name
    t = task name do
      cd i[:path] do
        sh "dub run --config=#{config} -- #{i[:arguments].join(' ')}"
      end
    end
    Rake::Task["run-all"].enhance([t])

    name = "build-#{i[:name]}-#{config}"
    desc name
    t = task name do
      cd i[:path] do
        sh "dub build --config=#{config}"
      end
    end
    Rake::Task["build-all"].enhance([t])

  end
end

