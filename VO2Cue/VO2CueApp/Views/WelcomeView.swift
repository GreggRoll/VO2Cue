import SwiftUI

struct WelcomeView: View {
    @Environment(PurchaseStore.self) private var purchases
    @State private var showingHeartRateSetup = false
    @State private var page: Page = .longGame
    let onComplete: () -> Void

    private enum Page: Int, CaseIterable, Identifiable {
        case longGame, feelFitter, followCues, yourWay
        var id: Self { self }
        var eyebrow: String {
            switch self {
            case .longGame: "INVEST IN YOUR FUTURE"
            case .feelFitter: "FEEL THE DIFFERENCE"
            case .followCues: "MEET YOUR INTERVAL COACH"
            case .yourWay: "MAKE IT A HABIT"
            }
        }
        var title: String {
            switch self {
            case .longGame: "More life.\nMore living."
            case .feelFitter: "Feel fitter.\nLook the part."
            case .followCues: "You move.\nWe cue."
            case .yourWay: "Your workout.\nYour way."
            }
        }
        var detail: String {
            switch self {
            case .longGame:
                "Train for a longer, healthier life. VO2Cue makes structured cardio easier to follow, one interval at a time."
            case .feelFitter:
                "Build the cardio habit behind better stamina, more energy, and a fitter you. Show up for the way you want to feel—and look."
            case .followCues:
                "Stop watching the clock. Voice, sound, and haptic cues tell you when to work, recover, and finish on iPhone or Apple Watch."
            case .yourWay:
                "Start with Norwegian 4×4 or build your own intervals. Run, ride, row, swim, or take your cardio to the gym."
            }
        }
    }

    var body: some View {
        if showingHeartRateSetup {
            HeartRateOnboardingView(isIntroduction: true, onComplete: onComplete)
        } else {
            introduction
        }
    }

    private var introduction: some View {
        VStack(spacing: 0) {
            HStack {
                Text("VO2Cue").font(.title3.bold())
                Spacer()
                Text("\(page.rawValue + 1) / \(Page.allCases.count + 1)")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    .accessibilityLabel("Introduction, step \(page.rawValue + 1) of \(Page.allCases.count + 1)")
            }
            .padding(.horizontal, 24).padding(.top, 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    illustration.padding(.top, 16)
                    Text(page.eyebrow).font(.caption.bold()).tracking(1.5).foregroundStyle(.secondary)
                    Text(page.title)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("onboardingTitle")
                    Text(page.detail).font(.body).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    pageBenefits
                }
                .frame(maxWidth: 560, alignment: .leading).frame(maxWidth: .infinity)
                .padding(.horizontal, 24).padding(.bottom, 24)
            }
            .id(page)
            VStack(spacing: 14) {
                HStack(spacing: 7) {
                    ForEach(Page.allCases) { step in
                        Capsule().fill(step == page ? OnboardingStyle.accent : Color.secondary.opacity(0.2))
                            .frame(width: step == page ? 24 : 7, height: 7)
                    }
                }
                .accessibilityHidden(true)
                OnboardingPrimaryButton(title: primaryTitle) {
                    if let next = Page(rawValue: page.rawValue + 1) { page = next }
                    else { showingHeartRateSetup = true }
                }
                .accessibilityIdentifier("onboardingContinue")
                if page != .longGame {
                    Button("Back") { page = Page(rawValue: page.rawValue - 1) ?? .longGame }
                        .font(.subheadline).foregroundStyle(.secondary).frame(minHeight: 30)
                } else {
                    Text("Your eyes-free interval coach").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 560).frame(maxWidth: .infinity)
            .padding(.horizontal, 24).padding(.vertical, 16).background(.background)
        }
        .background(.background)
        .interactiveDismissDisabled()
    }

    private var primaryTitle: String {
        "Continue"
    }

    private var illustration: some View {
        VStack(spacing: 12) {
            if page == .followCues {
                HStack(spacing: 10) {
                    ForEach(IntervalRound.allCases) { _ in
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 12).fill(OnboardingStyle.accent).frame(height: 56)
                                .overlay(Text("4").font(.largeTitle.bold()).foregroundStyle(.black))
                            Text("MIN HARD").font(.caption2.bold())
                        }
                    }
                }
                Text("Recover for 3 minutes between rounds").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Image(systemName: page == .longGame ? "heart.fill" : page == .feelFitter ? "figure.run" : "applewatch")
                    .font(.system(size: 48, weight: .medium)).foregroundStyle(OnboardingStyle.accent)
                    .accessibilityHidden(true)
                Text(page == .longGame ? "TRAIN FOR THE LONG GAME" : page == .feelFitter ? "BUILD A FITTER YOU" : "ONE APP. YOUR KIND OF CARDIO.")
                    .font(.caption.bold()).tracking(1)
            }
        }
        .padding(18).frame(maxWidth: .infinity)
        .background(OnboardingStyle.card, in: RoundedRectangle(cornerRadius: 28))
    }

    @ViewBuilder private var pageBenefits: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch page {
            case .longGame:
                OnboardingBenefit(symbol: "lungs.fill", title: "Cardio fitness matters", detail: "VO₂ max describes how much oxygen your body can use during hard exercise. It’s one measure of cardio fitness.")
                OnboardingBenefit(symbol: "heart.text.square", title: "Give your future self more", detail: "Regular physical activity supports heart health and can lower the risk of premature death.")
                Link("Explore the health benefits · CDC", destination: URL(string: "https://www.cdc.gov/physical-activity-basics/benefits/index.html")!).font(.footnote)
            case .feelFitter:
                OnboardingBenefit(symbol: "bolt.fill", title: "More stamina for real life", detail: "Work toward feeling less winded on the stairs, on a run, and in the moments that matter.")
                OnboardingBenefit(symbol: "figure.strengthtraining.traditional", title: "Support your fitness goals", detail: "Consistent cardio, balanced nutrition, and strength training can help you work toward a healthier weight and a fitter appearance.")
                Text("Progress depends on your routine and starting point. VO2Cue guides workouts; it doesn’t measure VO₂ max or guarantee health or appearance changes.").font(.footnote).foregroundStyle(.secondary)
            case .followCues:
                OnboardingBenefit(symbol: "waveform", title: "Focus on your effort", detail: "Get cues for phase changes and halfway points. Choose the sounds, voice, and haptics that suit you.")
                OnboardingBenefit(symbol: "lock.fill", title: "Keep your phone out of the way", detail: "iPhone audio continues with the screen locked. Apple Watch gives you workout controls and live heart rate.")
                Text("4×4 means four 4-minute hard efforts with 3-minute recoveries. The preset includes a warm-up. Adjust your effort and intervals to your fitness level.").font(.footnote).foregroundStyle(.secondary)
            case .yourWay:
                OnboardingBenefit(symbol: "slider.horizontal.3", title: "A plan that fits you", detail: "Customize work, recovery, rounds, warm-up, cool-down, and cue labels. Sync your profiles to Apple Watch.")
                OnboardingBenefit(symbol: "clock.arrow.circlepath", title: "See the work you’ve put in", detail: "Keep a workout history and optionally save completed sessions to Apple Health.")
                OnboardingBenefit(symbol: "hand.raised.fill", title: "Just you and your training", detail: "No account, ads, or tracking. Your workout profiles and history stay on your devices.")
                Text(purchases.isUnlocked ? "Your access is already unlocked. Thanks for supporting VO2Cue." : "Full access requires a monthly membership or a one-time lifetime purchase. Already bought the paid app? Your access stays included.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private enum IntervalRound: Int, CaseIterable, Identifiable {
        case first, second, third, fourth
        var id: Self { self }
    }
}
