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
    let description = "Manage Docker containers with Colima"
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
        let manager = DockerManagerState.shared.manager
        // Export backup data (manager handles this internally)
        return try await manager.exportBackupData()
    }
}

// MARK: - Docker Section (3 static items)

enum DockerSection: String, Identifiable, Hashable, CaseIterable {
    case colima = "Colima"
    case containers = "Containers"
    case images = "Images"

    var id: String { rawValue }
}

// MARK: - Shared State

@MainActor
class DockerManagerState: ObservableObject {
    static let shared = DockerManagerState()

    let alertQueue = AlertQueue()
    let toastQueue = ToastQueue()
    @Published var manager: DockerManager
    @Published var colimaInfo: ColimaInfo
    @Published var selectedSection: DockerSection? = .colima
    @Published var showingAddContainer = false
    @Published var showingEditContainer = false
    @Published var containerToEdit: ContainerRuntime?
    @Published var containerToDelete: ContainerRuntime?
    @Published var showingDeleteContainerConfirmation = false
    @Published var imageToDelete: ImageInfo?
    @Published var showingDeleteImageConfirmation = false

    // Private - access via getColimaRuntime() for detail views
    private var colimaRuntime: ColimaRuntime
    private var cancellables = Set<AnyCancellable>()

    private init() {
        self.manager = DockerManager(alertQueue: alertQueue, toastQueue: toastQueue)
        self.colimaRuntime = ColimaRuntime()
        self.colimaInfo = ColimaInfo(
            isRunning: false,
            processingAction: nil
        )

        // Forward manager changes to state
        manager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        .store(in: &cancellables)

        // Subscribe to colima changes to refresh colimaInfo
        colimaRuntime.objectWillChange.sink { [weak self] _ in
            self?.refreshColimaInfo()
        }
        .store(in: &cancellables)
    }

    /// Get full ColimaRuntime for detail views (on-demand)
    func getColimaRuntime() -> ColimaRuntime {
        return colimaRuntime
    }

    /// Refresh lightweight colimaInfo from runtime
    private func refreshColimaInfo() {
        colimaInfo = ColimaInfo(
            isRunning: colimaRuntime.isRunning,
            processingAction: colimaRuntime.processingAction
        )
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
                ToolbarButtonConfig(icon: "square.and.arrow.up", help: "Export Containers") {
                    state.manager.exportContainers()
                }
            ],
            items: DockerSection.allCases,
            emptyState: EmptyStateConfig(
                icon: "shippingbox",
                title: "Docker Manager",
                subtitle: "Manage Colima, containers, and images"
            ),
            selectedItem: Binding(
                get: { state.selectedSection },
                set: { state.selectedSection = $0 }
            )
        ) { section, isSelected in
            switch section {
            case .colima:
                return ModuleSidebarListItem(
                    icon: .image(systemName: "server.rack", color: state.colimaInfo.isRunning ? AppTheme.statusRunning : AppTheme.statusStopped),
                    title: "Colima",
                    subtitle: state.colimaInfo.isRunning ? "Running" : "Stopped",
                    badge: nil,
                    actions: [],
                    isSelected: isSelected,
                    onTap: {
                        state.selectedSection = .colima
                    }
                )

            case .containers:
                return ModuleSidebarListItem(
                    icon: .image(systemName: "shippingbox", color: .accentColor),
                    title: "Containers",
                    subtitle: "\(state.manager.containersList.count) containers",
                    badge: nil,
                    actions: [],
                    isSelected: isSelected,
                    onTap: {
                        state.selectedSection = .containers
                    }
                )

            case .images:
                return ModuleSidebarListItem(
                    icon: .image(systemName: "cube.fill", color: .accentColor),
                    title: "Images",
                    subtitle: "\(state.manager.imagesList.count) images",
                    badge: nil,
                    actions: [],
                    isSelected: isSelected,
                    onTap: {
                        state.selectedSection = .images
                    }
                )
            }
        }
        .sheet(isPresented: $state.showingAddContainer) {
            AddContainerView(manager: state.manager)
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
            Button("Delete", role: .destructive) {
                if let container = state.containerToDelete {
                    Task {
                        await state.manager.deleteContainer(id: container.id)
                        state.containerToDelete = nil
                    }
                }
            }
        } message: {
            if let container = state.containerToDelete {
                Text("Are you sure you want to delete '\(container.config.name)'? This action cannot be undone.")
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
}

// MARK: - Detail View

struct DockerManagerDetailView: View {
    @ObservedObject var state = DockerManagerState.shared
    @State private var colimaCheckComplete = false
    @State private var isCheckingColima = false

    var body: some View {
        Group {
            if !colimaCheckComplete {
                // Initial Colima check gate
                ColimaCheckGateView(
                    isChecking: $isCheckingColima,
                    onCheckComplete: {
                        colimaCheckComplete = true
                    }
                )
            } else if let selectedSection = state.selectedSection {
                switch selectedSection {
                case .colima:
                    ColimaDetailView()
                case .containers:
                    ContainersListDetailView()
                case .images:
                    ImagesListDetailView()
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)

                    Text("Select a Section")
                        .font(.title2)
                        .foregroundColor(.secondary)

                    Text("Choose Colima, Containers, or Images from the sidebar")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            // Check Colima status once on appear
            if !colimaCheckComplete && !isCheckingColima {
                isCheckingColima = true
                await state.getColimaRuntime().checkStatus()

                if state.colimaInfo.isRunning {
                    // If already running, complete check immediately
                    colimaCheckComplete = true
                }
                isCheckingColima = false
            }
        }
    }
}

// MARK: - Colima Check Gate View

struct ColimaCheckGateView: View {
    @ObservedObject var state = DockerManagerState.shared
    @Binding var isChecking: Bool
    let onCheckComplete: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            if isChecking {
                // Initial check
                ProgressView()
                    .scaleEffect(1.5)

                Text("Checking Colima status...")
                    .font(.headline)
                    .foregroundColor(.secondary)
            } else if state.colimaInfo.processingAction == .starting {
                // Starting Colima
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)

                    Text("Starting Colima...")
                        .font(.headline)

                    Text("This may take a few moments")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if !state.colimaInfo.isRunning {
                // Colima not running - show start option
                VStack(spacing: 20) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 64))
                        .foregroundColor(.orange)

                    Text("Colima is not running")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Docker containers require Colima to be running")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    VariantButton("Start Colima", icon: "play.fill", variant: .primary) {
                        startColimaAndWait()
                    }
                    .controlSize(.large)
                }
                .padding(40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: state.colimaInfo.isRunning) { _, newValue in
            if newValue && state.colimaInfo.processingAction == nil {
                // Colima is running and not processing - complete the gate
                onCheckComplete()
            }
        }
    }

    private func startColimaAndWait() {
        let colima = state.getColimaRuntime()
        colima.start()

        // Poll for completion
        Task {
            while state.colimaInfo.processingAction == .starting {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            }

            // Double-check status after start completes
            await colima.checkStatus()

            if state.colimaInfo.isRunning {
                await MainActor.run {
                    onCheckComplete()
                }
            }
        }
    }
}
