import SwiftUI

@MainActor
struct PaywallView: View {
  @ObservedObject var storeManager: StoreManager
  let dismissPaywall: () -> Void

  @State var selectedPlan: PlanKind = .lifetime
  @State var showSuccess = false
  @State var alertInfo: AlertInfo?

  struct AlertInfo: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let isRestore: Bool
  }

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        contentStack
          .padding(.horizontal, 22)
          .padding(.top, 18)
          .padding(.bottom, 18)
      }
      .scrollIndicators(.automatic)

      purchaseFooter
    }
    .frame(
      minWidth: minimumSheetWidth,
      idealWidth: sheetWidth,
      maxWidth: .infinity,
      minHeight: minimumSheetHeight,
      idealHeight: sheetHeight,
      maxHeight: .infinity
    )
    .background(sheetBackground)
    .task {
      await storeManager.loadProducts()
      await storeManager.refreshEntitlements()
      selectedPlan = defaultPlan
    }
    .onChange(of: storeManager.purchaseState) { _, newState in
      handlePurchaseStateChange(newState)
    }
    .onChange(of: storeManager.restoreState) { _, newState in
      handleRestoreStateChange(newState)
    }
    .overlay {
      if showSuccess {
        successOverlay
      }
    }
    .alert(alertInfo?.title ?? "", isPresented: .init(
      get: { alertInfo != nil },
      set: { isPresented in
        if !isPresented {
          if alertInfo?.isRestore == true {
            storeManager.restoreState = .idle
          } else {
            storeManager.purchaseState = .idle
          }
          alertInfo = nil
        }
      }
    ), presenting: alertInfo) { info in
      Button(LocalizedStringKey("OK")) {
        if info.isRestore {
          storeManager.restoreState = .idle
        } else {
          storeManager.purchaseState = .idle
        }
        alertInfo = nil
      }
    } message: { info in
      Text(info.message)
    }
  }
}
