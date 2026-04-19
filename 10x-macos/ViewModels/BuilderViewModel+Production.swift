import Foundation

extension BuilderViewModel {
    var productionGuide: ProductionGuide {
        ProductionGuideBuilder.build(
            projectName: activeProject?.name ?? "Untitled Project",
            fileTree: fileTree,
            environmentVariables: environmentVariables
        )
    }

    var productionChecklistSections: [ProductionChecklistSection] {
        ProductionChecklistBuilder.build(
            environmentVariables: environmentVariables,
            hasSupabaseIntegration: hasSupabaseRuntimeIntegration
        )
    }

    func saveProductionChecklistState(_ state: ProductionChecklistState) async {
        guard let project = activeProject else { return }
        productionChecklistState = state
        await localStore.saveProductionChecklist(
            state,
            projectName: project.name,
            projectId: project.id
        )
    }
}
