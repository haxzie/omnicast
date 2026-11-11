import SwiftUI

struct ModelsView: View {
    @EnvironmentObject private var environment: AppEnvironment

    private var models: ModelManager { environment.models }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Speech models").font(.system(size: 26, weight: .semibold))
                    Text("Download a model to transcribe entirely on this Mac. Nothing is uploaded.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                engineStatus

                ForEach(models.catalog) { model in
                    card(for: model)
                }
            }
            .padding(20)
        }
        .onAppear {
            models.refreshStates()
            Task { await models.refreshCatalog() }
        }
    }

    private var engineStatus: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: WhisperCLITranscriber().isAvailable ? "checkmark.seal" : "info.circle")
                    .foregroundStyle(WhisperCLITranscriber().isAvailable ? .green : .orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        WhisperCLITranscriber().isAvailable
                            ? "whisper.cpp engine detected"
                            : "Using Apple's on-device recognizer"
                    )
                    .font(.system(size: 13, weight: .medium))
                    Text(
                        WhisperCLITranscriber().isAvailable
                            ? "Downloaded models run through your local whisper.cpp build."
                            : "Install whisper.cpp (`brew install whisper-cpp`) to use the downloaded models. Until then dictation falls back to macOS speech recognition, which also runs locally."
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func card(for model: SpeechModel) -> some View {
        let state = models.states[model.id] ?? .notInstalled
        let isActive = models.activeModel?.id == model.id

        return GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(model.name).font(.system(size: 14, weight: .medium))
                    if model.recommended == true {
                        Tag(text: "Recommended", tint: .green)
                    }
                    if isActive {
                        Tag(text: "Active", tint: .accentColor)
                    }
                    Spacer()
                    Text(model.sizeDescription)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text(model.description).font(.system(size: 12)).foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    Tag(text: model.isMultilingual ? "99 languages" : "English", tint: .secondary)
                    Tag(text: "~\(Int(model.realtimeFactor))× realtime", tint: .secondary)
                    Tag(text: model.quality.rawValue.capitalized, tint: .secondary)
                }

                controls(for: model, state: state, isActive: isActive)
            }
        }
    }

    @ViewBuilder
    private func controls(for model: SpeechModel, state: ModelManager.State, isActive: Bool)
        -> some View
    {
        switch state {
        case .notInstalled:
            Button("Download") { models.download(model) }

        case .downloading(let progress, let written):
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: progress)
                HStack {
                    Text(
                        "\(ByteCountFormatter.string(fromByteCount: written, countStyle: .file)) of \(model.sizeDescription)"
                    )
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { models.cancelDownload(model) }.buttonStyle(.plain)
                }
            }

        case .installed:
            HStack(spacing: 8) {
                Button(isActive ? "In use" : "Use this model") {
                    environment.settings.selectedModelID = model.id
                }
                .disabled(isActive)
                Button("Remove") { models.delete(model) }
            }

        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Text(message).font(.system(size: 11)).foregroundStyle(.orange)
                Button("Try again") { models.download(model) }
            }
        }
    }
}

struct Tag: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.14)))
    }
}
