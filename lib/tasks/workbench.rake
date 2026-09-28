namespace :workbench do
  desc "Create (or rebuild) the synthetic Demo tour project; no provider is called"
  task demo: :environment do
    project = Workbench::DemoTour.build!
    puts "Demo tour ready: #{project.runs.count} Runs in project '#{project.slug}'. Open /projects/#{project.slug}"
  end

  namespace :demo do
    desc "Delete the Demo tour project and everything it owns"
    task remove: :environment do
      Workbench::DemoTour.remove!
      puts "Demo tour removed."
    end
  end
end
