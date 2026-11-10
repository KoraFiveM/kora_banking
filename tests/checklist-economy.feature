# Converted from the communitybot legacy tests by kora-qa-panel/scripts/convert-legacy.mjs.
# The """ block under each Scenario is the original test text, verbatim. Review before applying.
Feature: kora_banking — Economy

  @kora_banking @checklist @checklist:kora_banking:bank-branch-open @cat:economy
  Scenario: Open bank branch app
    """
    Checklist test: Walk to a branch (e.g. Fleeca Legion Square) and use the Open target: banking app opens with accounts, cash, transfer tabs.
    """
    When I go to "legion_square"
    And I manually: walk to the Fleeca Bank branch counter and select the Open target option
    Then the "kora_banking:bank" app opens
    And I confirm: the banking app shows accounts, cash and transfer tabs

  @kora_banking @checklist @checklist:kora_banking:bank-map-markers @cat:economy @manual
  Scenario: Bank map markers
    """
    Checklist test: Grouped Bank blips show for 6 Fleeca branches, Pacific Standard and Blaine County Savings.
    """
    When I manually: open the full map
    Then I confirm: grouped Bank blips show for the 6 Fleeca branches, Pacific Standard and Blaine County Savings

  @kora_banking @checklist @checklist:kora_banking:deposit-withdraw @cat:economy
  Scenario: Deposit and withdraw cash
    """
    Checklist test: Branch Cash tab: deposit and withdraw with account select and reference; balances update.
    """
    Given my cash balance is 500
    When I manually: go to a bank branch
    And I manually: open the banking app
    Then the "kora_banking:bank" app opens
    When I manually: open the Cash tab, select an account, enter a reference and deposit some cash
    Then I confirm: my balances update after the deposit
    When I manually: withdraw some cash with an account selected and a reference
    Then I confirm: my balances update after the withdrawal

  @kora_banking @checklist @checklist:kora_banking:transfer-player @cat:economy
  Scenario: Transfer to another player
    """
    Checklist test: Transfer tab: send to citizen ID, shared/society/gang account name or card number; offline players credited.
    """
    When I manually: go to a bank branch and open the banking app
    Then the "kora_banking:bank" app opens
    When I manually: go to the Transfer tab
    And I manually: send money to a citizen ID, a shared, society or gang account name, and a card number
    And I manually: send money to an offline player's citizen ID
    Then I confirm: each transfer succeeds and the recipients are credited, including the offline player

  @kora_banking @checklist @checklist:kora_banking:transaction-history @cat:economy
  Scenario: Account activity and statements
    """
    Checklist test: Activity tab lists type, amount, reference, date; sortable.
    """
    When I manually: go to a bank branch and open the banking app
    Then the "kora_banking:bank" app opens
    When I manually: go to the Activity tab
    Then I confirm: the list shows type, amount, reference and date for each entry
    And I confirm: the list can be sorted

  @kora_banking @checklist @checklist:kora_banking:order-card-pin @cat:economy
  Scenario: Order bank card and set PIN
    """
    Checklist test: At a branch order a bank card and choose a PIN; bank_card item appears in inventory.
    """
    Given I have no "bank_card"
    When I manually: go to a bank branch and open the banking app
    Then the "kora_banking:bank" app opens
    When I manually: order a bank card and choose a PIN
    Then I should have 1 "bank_card"

  @kora_banking @checklist @checklist:kora_banking:atm-use @cat:economy
  Scenario: Use ATM with card and PIN
    """
    Checklist test: Target an ATM with a card in inventory: card animation, progress bar, unlock with PIN, withdraw/deposit.
    """
    Given I have 1 "bank_card"
    When I manually: go to an ATM and target it with Use ATM
    Then I confirm: the card animation plays
    And a progress bar should run
    When I manually: enter my card PIN to unlock the ATM
    Then I confirm: the ATM unlocks with the PIN
    When I manually: withdraw some cash at the ATM
    And I manually: deposit some cash at the ATM
    Then I confirm: withdraw and deposit both work

  @kora_banking @checklist @checklist:kora_banking:atm-no-card @cat:economy
  Scenario: ATM without card
    """
    Checklist test: Target an ATM with no bank card: only an error notification shows.
    """
    Given I have no "bank_card"
    When I manually: go to an ATM and target it with Use ATM
    Then I should see a notification containing "You need a bank card to use an ATM."
    And I confirm: no animation or progress bar plays and the ATM does not open

  @kora_banking @checklist @checklist:kora_banking:atm-pin-throttle @cat:economy
  Scenario: ATM wrong-PIN throttling
    """
    Checklist test: Enter wrong PIN repeatedly; attempts are throttled and the ATM refuses.
    """
    Given I have 1 "bank_card"
    When I manually: go to an ATM, target it and enter a wrong PIN
    Then I should see a notification containing "Invalid PIN."
    When I manually: keep entering wrong PINs repeatedly
    Then I confirm: after repeated wrong PINs the attempts are throttled and the ATM refuses further attempts

  @kora_banking @checklist @checklist:kora_banking:atm-daily-limit @cat:economy
  Scenario: ATM daily withdrawal limit
    """
    Checklist test: Withdraw at ATM until daily allowance reached; remaining limit shown and further withdrawals refused.
    """
    Given I have 1 "bank_card"
    And my bank balance is at least 20000
    When I manually: go to an ATM, unlock it with my PIN and withdraw cash repeatedly until the daily allowance is reached
    Then I confirm: the remaining daily limit is shown (only applies when Config.useDailyLimit is enabled)
    And I confirm: further withdrawals are refused once the limit is reached

  @kora_banking @checklist @checklist:kora_banking:atm-vehicle-distance @cat:economy
  Scenario: ATM closes in vehicle or when walking away
    """
    Checklist test: Open ATM then enter a vehicle or move 3m away: ATM closes; ATM cannot be opened from vehicle.
    """
    Given I have 1 "bank_card"
    And a "test_car" is spawned in front of me
    When I manually: go to an ATM and open it with my card and PIN
    And I manually: walk more than 3 metres away from the ATM
    Then I confirm: the ATM closes
    When I manually: open the ATM again
    And I get in the vehicle
    Then I confirm: the ATM closes when I enter the vehicle
    When I manually: try to open the ATM while sitting in the vehicle
    Then I should see a notification containing "You cannot use an ATM from a vehicle."

  @kora_banking @checklist @checklist:kora_banking:shared-accounts @cat:economy @manual
  Scenario: Shared accounts (create/rename/delete)
    """
    Checklist test: At Pacific Standard create, rename and delete a shared account; Fleeca shows "Available at Pacific Standard".
    """
    When I manually: go to Pacific Standard and open the banking app
    And I manually: create a shared account, rename it, then delete it
    Then I confirm: create, rename and delete all work
    When I manually: go to a Fleeca branch and open the banking app
    Then I confirm: shared accounts show "Available at Pacific Standard" (only applies when Config.tiers.enabled is true)

  @kora_banking @checklist @checklist:kora_banking:shared-members @cat:economy @manual
  Scenario: Add/remove shared account members
    """
    Checklist test: Pacific Standard: grant and revoke member access; member can use the account.
    """
    When I manually: go to Pacific Standard and open the banking app on a shared account
    And I manually: grant member access to a second player
    And I manually: ask a second player to use the shared account
    Then I confirm: the other player can use the shared account
    When I manually: revoke the member's access
    And I manually: ask the second player to use the shared account again
    Then I confirm: the other player can no longer use the shared account

  @kora_banking @checklist @checklist:kora_banking:bank-tiers-limits @cat:economy @manual
  Scenario: Tier limits (Fleeca vs Pacific Standard)
    """
    Checklist test: With tiers on: Fleeca max transfer $10k and $5k daily counter withdrawal; Pacific Standard $250k and $50k.
    """
    When I manually: at a Fleeca branch, try a transfer above $10,000
    Then I confirm: the transfer is refused (only applies when Config.tiers.enabled is true)
    When I manually: at a Fleeca branch, withdraw over $5,000 in a day
    Then I confirm: the withdrawal above the $5,000 daily counter limit is refused
    When I manually: at Pacific Standard, try a transfer above $250,000
    And I manually: at Pacific Standard, withdraw over $50,000 in a day
    Then I confirm: transfers above $250k and withdrawals above $50k are refused, lower amounts work

  @kora_banking @checklist @checklist:kora_banking:society-gang-accounts @cat:economy @manual
  Scenario: Society and gang accounts
    """
    Checklist test: Job/gang accounts show as separate balances; bosses can use them; boss menu bonuses debit the society account.
    """
    When I manually: as a job or gang boss, open the banking app at a branch
    Then I confirm: job and gang accounts show as separate balances
    When I manually: use the society account as boss
    Then I confirm: the boss can use the society account
    When I manually: pay a bonus from the boss menu
    Then I confirm: the bonus is debited from the society account

  @kora_banking @checklist @checklist:kora_banking:givecash-command @cat:economy
  Scenario: /givecash
    """
    Checklist test: Run /givecash <id> <amount> near another player; cash moves between them.
    """
    Given my cash balance is 500
    When I manually: stand near a second player and note their id
    And I manually: run /givecash with the other player's id and an amount of 100
    Then I should see a notification containing "Gave $"
    And my cash balance should have changed by -100
    And I confirm: the other player sees a "Received $" notification and their cash increases by 100

  @kora_banking @checklist @checklist:kora_banking:qb-banking-compat @cat:economy @manual
  Scenario: AddMoney/RemoveMoney compat exports
    """
    Checklist test: Legacy job resources paying via qb-banking AddMoney/RemoveMoney credit the right account.
    """
    When I manually: trigger a legacy job resource payment that uses qb-banking AddMoney
    Then I confirm: the correct account is credited
    When I manually: trigger a legacy job resource payment that uses qb-banking RemoveMoney
    Then I confirm: the correct account is debited
