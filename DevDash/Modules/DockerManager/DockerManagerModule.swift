//
//  DockerManagerModule.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-25.
//

import SwiftUI
import Combine

struct DockerManagerModule: DevDashModule {
    let id = "docker-manager"
    let name = "Docker Manager"
    let icon = "shippingbox.fill"
    let description = "Containers on Colima and Apple Containers"
    let accentColor = Color.blue

    func makeSidebarView() -> AnyView {
        AnyView(DockerManagerSidebarView())
    }

    func makeDetailView() -> AnyView {
        AnyView(DockerManagerDetailView())
    }

    // MARK: - Backup Support

    var backupFileName: String {
        "containers.json"
    }

    func exportForBackup() async throws -> Data {
        try await DockerManagerState.shared.manager.exportBackupData()
    }
}

// MARK: - Docker Section (engine host, then its containers and images)

enum DockerSection: Identifiable, Hashable {
    case host(ContainerEngine)
    case containers(ContainerEngine)
    case images(ContainerEngine)

    var id: String {
        switch self {
        case .host(let e): return "host-\(e.rawValue)"
        case .containers(let e): return "containers-\(e.rawValue)"
        case .images(let e): return "images-\(e.rawValue)"
        }
    }

    var engine: ContainerEngine {
        switch self {
        case .host(let e), .containers(let e), .images(let e): return e
        }
    }

    static let all: [DockerSection] = ContainerEngine.allCases.flatMap { [.host($0), .containers($0), .images($0)] }
}

// MARK: - Shared State

@MainActor
class DockerManagerState: ObservableObject {
    static let shared = DockerManagerState()

    let alertQueue = AlertQueue()
    let toastQueue = ToastQueue()
    @Published var manager: DockerManager
    @Published var engineInfo: [ContainerEngine: EngineInfo] = [:]
    @Published var selectedSection: DockerSection? = .containers(.apple)
    @Published var showingAddContainer = false
    @Published var showingEditContainer = false
    @Published var containerToEdit: ContainerRuntime?
    @Published var containerToDelete: ContainerRuntime?
    @Published var showingDeleteContainerConfirmation = false
    @Published var imageToDelete: ImageInfo?
    @Published var showingDeleteImageConfirmation = false

    // Private - access via engineRuntime(_:) for detail views
    private var engineRuntimes: [ContainerEngine: EngineRuntime] = [:]
    private var cancellables = Set<AnyCancellable>()

    /// Engine of the selected section. New containers default to it.
    var selectedEngine: ContainerEngine { selectedSection?.engine ?? .apple }

    private init() {
        self.manager = DockerManager(alertQueue: alertQueue, toastQueue: toastQueue)

        // Forward manager changes to state
        manager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        .store(in: &cancellables)

        for engine in ContainerEngine.allCases {
            let runtime = EngineRuntime(engine: engine)
            engineRuntimes[engine] = runtime
            engineInfo[engine] = EngineInfo(isRunning: false, processingAction: nil)
            // Refresh lightweight engineInfo when the host changes
            Publishers.CombineLatest3(runtime.$isRunning, runtime.$processingAction, runtime.$colima)
                .sink { [weak self] running, action, colima in
                    self?.engineInfo[engine] = EngineInfo(isRunning: running, processingAction: action,
                                                          isSetUp: engine != .docker || colima != nil)
                }
                .store(in: &cancellables)
        }
    }

    /// Full EngineRuntime for detail views (on-demand)
    func engineRuntime(_ engine: ContainerEngine) -> EngineRuntime {
        engineRuntimes[engine]!
    }

    func isRunning(_ engine: ContainerEngine) -> Bool {
        engineInfo[engine]?.isRunning == true
    }
}

// MARK: - Sidebar View

struct DockerManagerSidebarView: View {
    @ObservedObject var state = DockerManagerState.shared

    var body: some View {
        ModuleSidebarList(
            toolbarButtons: [
                ToolbarButtonConfig(icon: "plus.circle", help: "Add Container") {
                    state.showingAddContainer = true
                },
                ToolbarButtonConfig(icon: "square.and.arrow.down", help: "Import Containers") {
                    state.manager.importContainers()
                },
                ToolbarButtonConfig(icon: "square.and.arrow.up", help: "Export Containers") {
                    state.manager.exportContainers()
                }
            ],
            items: DockerSection.all,
            emptyState: EmptyStateConfig(
                icon: "shippingbox",
                title: "Docker Manager",
                subtitle: "Manage engines, containers, and images"
            ),
            selectedItem: Binding(
                get: { state.selectedSection },
                set: { state.selectedSection = $0 }
            )
        ) { section, isSelected in
            row(section, isSelected: isSelected)
        }
        .sheet(isPresented: $state.showingAddContainer) {
            AddContainerView(manager: state.manager, engine: state.selectedEngine)
        }
        .sheet(isPresented: $state.showingEditContainer) {
            if let container = state.containerToEdit {
                EditContainerView(manager: state.manager, container: container)
            }
        }
        .alertQueue(state.alertQueue)
        .alert("Delete Container", isPresented: $state.showingDeleteContainerConfirmation) {
            Button("Cancel", role: .cancel) {
                state.containerToDelete = nil
            }
            Button("Remove from DevDash") {
                if let container = state.containerToDelete {
                    state.manager.removeContainer(id: container.id)
                }
                state.containerToDelete = nil
            }
            Button("Delete Container", role: .destructive) {
                if let container = state.containerToDelete {
                    Task {
                        await state.manager.deleteContainer(id: container.id)
                        state.containerToDelete = nil
                    }
                }
            }
        } message: {
            if let container = state.containerToDelete {
                Text("'Remove from DevDash' keeps the container in \(container.config.resolvedEngine.hostName). 'Delete Container' also deletes it there. That cannot be undone.")
            }
        }
        .alert("Delete Image", isPresented: $state.showingDeleteImageConfirmation) {
            Button("Cancel", role: .cancel) {
                state.imageToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let image = state.imageToDelete {
                    Task {
                        await state.manager.deleteImage(image)
                        state.imageToDelete = nil
                    }
                }
            }
        } message: {
            if let image = state.imageToDelete {
                Text("Are you sure you want to delete '\(image.id)'? This action cannot be undone.")
            }
        }
        .onAppear {
            AppTheme.AccentColor.shared.set(.blue)
        }
    }

    private func row(_ section: DockerSection, isSelected: Bool) -> ModuleSidebarListItem {
        let engine = section.engine
        let select = { state.selectedSection = section }
        switch section {
        case .host:
            let running = state.isRunning(engine)
            let setUp = state.engineInfo[engine]?.isSetUp ?? true
            return ModuleSidebarListItem(
                icon: .image(systemName: engine == .docker ? "server.rack" : "apple.logo",
                             color: running ? AppTheme.statusRunning : AppTheme.statusStopped),
                title: engine.hostName,
                subtitle: running ? "Running" : setUp ? "Stopped" : "Not set up",
                isSelected: isSelected,
                onTap: select
            )
        case .containers:
            let found = state.manager.discovered[engine]?.count ?? 0
            return ModuleSidebarListItem(
                icon: .image(systemName: "shippingbox", color: .accentColor),
                title: "Containers",
                subtitle: "\(state.manager.containers(for: engine).count) containers",
                badge: found > 0 ? Badge("\(found) new", variant: .warning) : nil,
                isSelected: isSelected,
                indent: 20,
                onTap: select
            )
        case .images:
            return ModuleSidebarListItem(
                icon: .image(systemName: "cube.fill", color: .accentColor),
                title: "Images",
                subtitle: "\(state.manager.images[engine]?.count ?? 0) images",
                isSelected: isSelected,
                indent: 20,
                onTap: select
            )
        }
    }
}

// MARK: - Detail View

struct DockerManagerDetailView: View {
    @ObservedObject var state = DockerManagerState.shared

    var body: some View {
        if let section = state.selectedSection {
            Group {
                switch section {
                case .host(let engine):
                    EngineDetailView(host: state.engineRuntime(engine))
                case .containers(let engine):
                    ContainersListDetailView(engine: engine)
                case .images(let engine):
                    ImagesListDetailView(engine: engine)
                }
            }
            .id(section)  // Reset view state when switching engine
        } else {
            VStack(spacing: 16) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 64))
                    .foregroundColor(.secondary)

                Text("Select a Section")
                    .font(.title2)
                    .foregroundColor(.secondary)

                Text("Choose an engine, its containers, or its images from the sidebar")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Engine Not Running

/// Shown in place of containers/images when the engine host is stopped.
struct EngineStoppedView: View {
    @ObservedObject var host: EngineRuntime

    var body: some View {
        VStack(spacing: 20) {
            if host.processingAction == .starting {
                ProgressView().scaleEffect(1.5)
                Text("Starting \(host.name)...").font(.headline)
                Text("This may take a few moments").font(.caption).foregroundColor(.secondary)
            } else if host.engine == .docker && host.colima == nil {
                Image(systemName: "server.rack")
                    .font(.system(size: 64))
                    .foregroundColor(.orange)
                Text("Colima is not set up")
                    .font(.title2)
                    .fontWeight(.semibold)
                VariantButton("Set Up Colima", icon: "plus", variant: .primary) {
                    DockerManagerState.shared.selectedSection = .host(.docker)
                }
                .controlSize(.large)
            } else {
                Image(systemName: "server.rack")
                    .font(.system(size: 64))
                    .foregroundColor(.orange)
                Text("\(host.name) is not running")
                    .font(.title2)
                    .fontWeight(.semibold)
                VariantButton("Start \(host.name)", icon: "play.fill", variant: .primary) {
                    host.start()
                }
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
