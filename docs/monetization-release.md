# Free download, paid access

The new iPhone flow has four introduction pages, followed by a hard paywall for
customers without access. Both plans unlock the same iPhone and Apple Watch
features. Existing paid-app buyers keep lifetime access.

| Product | App Store Connect type | US price | Product ID |
| --- | --- | --- | --- |
| Monthly membership | Auto-renewable subscription, 1 month | $1.99/month | `com.gregadams.vo2cue.monthly` |
| Lifetime access | Non-consumable in-app purchase | $19.99 once | `com.gregadams.vo2cue.lifetime` |

Lifetime is a one-time purchase, not an auto-renewable subscription. StoreKit
supplies localized prices in the real purchase UI. Unavailable products cannot
be purchased; the app offers retry, restore, and help. The fixed USD prices used
by Debug UI fixtures never appear in Release builds.

## App Store Connect catalog verification

On October 12, 2026, the two matching products were created and verified in
App Store Connect: monthly Apple ID `6822101918` and lifetime Apple ID
`6822101878`. Both are `READY_TO_SUBMIT`, with English names/descriptions,
completed paywall review screenshots, availability in 175 territories, and
the US prices above. Monthly pricing is configured in all 175 territories;
lifetime pricing uses the US base price and Apple's automatic equalization.

The old products `vo2cuepro` (consumable) and `vo2cuepromonthly` do not match
the app's product IDs and remain untouched. Do not switch the app's lifetime
ID to the consumable: it cannot supply restorable permanent access.

Apple's sandbox, including TestFlight, can take up to one hour to reflect
catalog changes. Tap **Try again** after propagation. The existing build
already requests the corrected IDs, so this fix does not require rebuilding.
Sandbox testing does not require product review approval; production still
requires submission with the first app update offering these purchases.
Verify actual price loading, both checkout paths, and restoration in TestFlight.
See [Apple's sandbox availability troubleshooting](https://developer.apple.com/documentation/technotes/tn3186-troubleshooting-in-app-purchases-availability-in-the-sandbox).

## Coordinate the first free release

1. Create the monthly subscription group and product, then the lifetime
   non-consumable, using the IDs above. Add pricing, localizations, review
   screenshots, and availability. Both products must be submitted with the
   first app update that offers them. Confirm Paid Apps Agreement, banking,
   and tax details in App Store Connect.
2. Decide the scheduled change from paid to Free. Set
   `PurchaseConfiguration.paidDownloadCutoff` in `VO2Cue/Shared/PurchaseAccess.swift`
   to its UTC instant, then build the release. **Do not release the free download
   with the cutoff still nil.** Nil deliberately preserves the current paid-app
   model for verified production app purchases and keeps the current Watch
   experience available. Sandbox and TestFlight acquisitions do not receive
   paid-buyer access.
3. Use manual release to coordinate the approved app and approved products with
   the Free price schedule. Storefront pricing and app distribution can propagate
   at different times. Choose a buyer-friendly cutoff that covers the last paid
   sales; a short overlap may grant some early free downloads lifetime access.
   Avoid any interval in which a customer can pay to download and then be charged
   again. Keep the same app record and bundle identifier.
4. Tell App Review that new free downloads require either plan and that verified
   original paid-app purchases retain full access. Describe ongoing value from
   substantive app updates for the monthly membership. Update the App Store
   description and screenshots to disclose the paid access requirement.
5. Verify in sandbox/TestFlight: both purchase types, restore on a reinstall,
   cancellation, pending approval, expired/refunded transactions, renewal,
   billing grace period if enabled, and Watch sync. Verify the paid-buyer branch
   with an actual production paid-app purchase; sandbox receipts cannot prove it.

The migration uses Apple's verified `AppTransaction.originalPurchaseDate`,
compared with the configured cutoff. It does not use first-launch dates or local
onboarding flags as evidence of a purchase. The cutoff is a date rather than
only a build number because an old build may remain downloadable around the
price change. The purchase scan must finish before a new purchase is enabled.
An unverifiable app purchase offers retry/restoration instead of charging a
potential existing buyer again.

StoreKit's `Transaction.currentEntitlements` supplies current IAP access,
including billing grace periods. Verified lifetime and monthly purchases unlock
the app; revoked/refunded purchases do not. Monthly cancellation retains access
through the paid period. Transaction updates and foreground refreshes recheck
access. A workout already in progress is allowed to finish.

The paired phone syncs its access state alongside workout profiles. The Watch
also checks StoreKit entitlements. Synced monthly access expires at the verified
paid/grace-period expiry; paid-app and lifetime access allow independent Watch
use after syncing. A locked Watch directs users to choose or restore a plan on
iPhone. Test actual paired devices before release, including offline use and
renewal/revocation propagation.

## Review locally

The shared **VO2Cue Purchases** scheme selects
`VO2Cue/VO2CueTests/VO2Cue.storekit` for local StoreKit testing. It does not create
products in App Store Connect and is not embedded in the shipping app. Keep the
normal **VO2Cue** scheme for sandbox/TestFlight and release builds.

The unit-test target is hosted by VO2Cue so StoreKit Test runs in an app context.
The host skips its automatic StoreKit startup while unit tests are running.
Purchase tests disable only the original-paid-app receipt check; they exercise
real StoreKit Test products and signed IAP entitlements. Separate policy tests
cover the paid-buyer date boundary; a production receipt check is still required
before launch.

Local StoreKit testing succeeded on the installed iOS 17.5 simulator with ad hoc
simulator signing. The installed iOS 26.3 runtime refused StoreKit Test requests
with `SKInternalErrorDomain Code=3` and `notEntitled`. Use iOS 17.5 for the purchase
suite here. The onboarding/paywall UI tests run on iOS 26.3.

For a UI-only simulator review, launch a Debug build with:

```
-resetOnboarding -hasAlreadyReviewed YES -purchaseFixture locked
```

The `paid` and `lifetime` fixtures show the unlocked experience. Fixtures are
excluded from Release builds and cannot initiate purchases. UI tests verify the
four-page flow, locked relaunch, and paid/lifetime buyer access. Unit tests cover
the migration boundary and the Watch access payload/expiry. Five StoreKit tests
cover product configuration, verified checkout, cold-store restoration/refund,
monthly cancellation/expiry, and pending approval.

## Messaging

The onboarding leads with a longer, healthier life and a fitter appearance,
then demonstrates the interval cues, Norwegian 4×4, custom profiles, Apple Watch,
history, optional Health saving, and device-local data. It explains that VO2Cue
guides workouts and does not measure VO₂ max or guarantee changes. The CDC link
grounds the claims about activity, heart health, weight management, and reduced
risk of premature death:
https://www.cdc.gov/physical-activity-basics/benefits/index.html

Apple's migration and subscription guidance:

- https://developer.apple.com/documentation/storekit/supporting-business-model-changes-by-using-the-app-transaction
- https://developer.apple.com/app-store/review/guidelines/#subscriptions

The paywall includes Apple's standard EULA and the existing privacy policy.
There is no trial or free workout tier. Existing users can replay the
introduction from Settings. Rating requests are considered after completed
workouts, rather than immediately before or after the paywall.
