import XCTest

@MainActor final class BrowserUITests: XCTestCase {
  private func assertDisplayedText(
    _ text: String, in element: XCUIElement, file: StaticString = #filePath, line: UInt = #line
  ) {
    let predicate = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text)
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
    XCTAssertEqual(
      XCTWaiter.wait(for: [expectation], timeout: 5), .completed,
      "Expected \(text) in \(element)", file: file, line: line)
  }

  private func assertSelectedResult(
    _ id: String, name: String, in app: XCUIApplication,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let results = app.descendants(matching: .any).matching(identifier: "entityResults").firstMatch
    let row = results.tableRows.containing(.any, identifier: "entity-\(id)").firstMatch
    XCTAssertTrue(row.exists, results.debugDescription, file: file, line: line)
    let selected = NSPredicate(format: "selected == true")
    XCTAssertEqual(
      XCTWaiter.wait(
        for: [XCTNSPredicateExpectation(predicate: selected, object: row)], timeout: 3),
      .completed, "Expected \(id) to be highlighted", file: file, line: line)
    XCTAssertEqual(results.tableRows.matching(selected).count, 1, file: file, line: line)
    assertDisplayedText(name, in: app.staticTexts["entityDetailName"], file: file, line: line)
  }

  func testScrollingClickingAndKeyboardNavigationKeepOnePosition() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchEnvironment["AETHER_UI_TESTING"] = "1"
    app.launchEnvironment["AETHER_UI_SORTING"] = "1"
    app.launchEnvironment["AETHER_UI_TEST_SESSION"] = UUID().uuidString
    app.launch()
    let results = app.tables["entityResults"]
    let first = app.descendants(matching: .any)["entity-Item:61"]
    XCTAssertTrue(first.waitForExistence(timeout: 10))
    first.click()
    app.typeKey("s", modifierFlags: [])
    assertSelectedResult("Item:60", name: "Fixture Item 060", in: app)
    app.typeKey("w", modifierFlags: [])
    assertSelectedResult("Item:61", name: "Fixture Item 061", in: app)

    // Leave the selected row far outside the viewport, then click a visible row.
    results.scroll(byDeltaX: 0, deltaY: -1600)
    let id = 33
    let row = app.descendants(matching: .any)["entity-Item:\(id)"]
    XCTAssertTrue(row.exists)
    XCTAssertGreaterThan(row.frame.midY, results.frame.minY + 80)
    XCTAssertLessThan(row.frame.midY, results.frame.maxY - 80)
    let position = row.frame.midY
    row.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).click()
    assertSelectedResult("Item:\(id)", name: String(format: "Fixture Item %03d", id), in: app)
    XCTAssertEqual(row.frame.midY, position, accuracy: 2)
    app.typeKey("s", modifierFlags: [])
    assertSelectedResult(
      "Item:\(id - 1)", name: String(format: "Fixture Item %03d", id - 1), in: app)
    app.typeKey(.upArrow, modifierFlags: [])
    assertSelectedResult("Item:\(id)", name: String(format: "Fixture Item %03d", id), in: app)
    app.typeKey("w", modifierFlags: [])
    assertSelectedResult(
      "Item:\(id + 1)", name: String(format: "Fixture Item %03d", id + 1), in: app)
    app.typeKey(.downArrow, modifierFlags: [])
    assertSelectedResult("Item:\(id)", name: String(format: "Fixture Item %03d", id), in: app)
    app.buttons["Load More"].click()
    XCTAssertTrue(app.staticTexts["61 loaded"].waitForExistence(timeout: 5))
    XCTAssertEqual(row.frame.midY, position, accuracy: 2)
    row.click()
    app.typeKey(.return, modifierFlags: [])
    assertSelectedResult("Item:\(id)", name: String(format: "Fixture Item %03d", id), in: app)
    XCTAssertEqual(row.frame.midY, position, accuracy: 2)

    app.typeKey("f", modifierFlags: .command)
    app.searchFields.firstMatch.typeText("ws")
    XCTAssertEqual(app.searchFields.firstMatch.value as? String, "ws")
    XCTAssertTrue(app.staticTexts["No matching entities"].waitForExistence(timeout: 5))
  }

  func testHistorySelectionDoesNotRecordVisits() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchEnvironment["AETHER_UI_TESTING"] = "1"
    app.launchEnvironment["AETHER_UI_SORTING"] = "1"
    app.launchEnvironment["AETHER_UI_TEST_SESSION"] = UUID().uuidString
    app.launch()
    let first = app.descendants(matching: .any)["entity-Item:61"]
    XCTAssertTrue(first.waitForExistence(timeout: 10))
    first.click()
    assertSelectedResult("Item:61", name: "Fixture Item 061", in: app)
    for id in [60, 59] {
      app.typeKey("s", modifierFlags: [])
      assertSelectedResult("Item:\(id)", name: String(format: "Fixture Item %03d", id), in: app)
    }
    let history = app.descendants(matching: .any).matching(identifier: "sidebar-history").firstMatch
    history.click()
    XCTAssertTrue(app.staticTexts["3 saved locally"].waitForExistence(timeout: 5))
    let middle = app.descendants(matching: .any)["entity-Item:60"]
    let last = app.descendants(matching: .any)["entity-Item:61"]
    XCTAssertLessThan(middle.frame.minY, last.frame.minY)
    let position = last.frame.midY
    app.descendants(matching: .any)["entity-Item:59"].click()
    for id in [60, 61] {
      app.typeKey(.downArrow, modifierFlags: [])
      assertSelectedResult("Item:\(id)", name: String(format: "Fixture Item %03d", id), in: app)
    }
    app.typeKey("w", modifierFlags: [])
    assertSelectedResult("Item:60", name: "Fixture Item 060", in: app)
    app.typeKey("s", modifierFlags: [])
    assertSelectedResult("Item:61", name: "Fixture Item 061", in: app)
    XCTAssertEqual(last.frame.midY, position, accuracy: 2)
    app.descendants(matching: .any).matching(identifier: "category-Item").firstMatch.click()
    history.click()
    XCTAssertLessThan(middle.frame.minY, last.frame.minY)
    // Opening the same preview from another list is a new visit, even with
    // already loaded details. History selection must not disable future visits.
    app.descendants(matching: .any).matching(identifier: "category-Item").firstMatch.click()
    first.click()
    history.click()
    XCTAssertLessThan(last.frame.minY, middle.frame.minY)
    app.terminate()
    app.launch()
    app.descendants(matching: .any).matching(identifier: "sidebar-history").firstMatch.click()
    XCTAssertTrue(app.staticTexts["3 saved locally"].waitForExistence(timeout: 5))
    XCTAssertLessThan(last.frame.minY, middle.frame.minY)
  }

  func testSortingUsesTheEntireCategoryAndSearchBeforePagination() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchEnvironment["AETHER_UI_TESTING"] = "1"
    app.launchEnvironment["AETHER_UI_SORTING"] = "1"
    app.launchEnvironment["AETHER_UI_TEST_SESSION"] = UUID().uuidString
    app.launch()
    let newest = app.descendants(matching: .any)["entity-Item:61"]
    let alphabetical = app.descendants(matching: .any)["entity-Item:1"]
    let highestLevel = app.descendants(matching: .any)["entity-Item:2"]
    XCTAssertTrue(newest.waitForExistence(timeout: 10))
    XCTAssertFalse(alphabetical.exists)
    func sort(_ label: String) {
      app.menuButtons["resultSort"].click()
      app.menuItems[label].click()
    }
    sort("Name")
    XCTAssertTrue(alphabetical.waitForExistence(timeout: 5))
    XCTAssertLessThan(alphabetical.frame.minY, highestLevel.frame.minY)
    XCTAssertTrue(app.staticTexts["50 loaded"].exists)
    app.buttons["Load More"].click()
    XCTAssertTrue(app.staticTexts["61 loaded"].waitForExistence(timeout: 5))
    sort("Level (highest first)")
    XCTAssertTrue(highestLevel.waitForExistence(timeout: 5))
    XCTAssertLessThan(highestLevel.frame.minY, newest.frame.minY)
    app.searchFields.firstMatch.click()
    app.searchFields.firstMatch.typeText("Fixture Item")
    XCTAssertTrue(app.staticTexts["Results for “Fixture Item”"].waitForExistence(timeout: 5))
    sort("Name")
    XCTAssertTrue(alphabetical.waitForExistence(timeout: 5))
    XCTAssertLessThan(alphabetical.frame.minY, highestLevel.frame.minY)
    app.typeKey(.escape, modifierFlags: [])
    let picker = app.descendants(matching: .any).matching(identifier: "gameLanguagePicker")
      .firstMatch
    picker.radioButtons["🇩🇪"].click()
    XCTAssertTrue(newest.waitForExistence(timeout: 5))
    assertDisplayedText("Aal im Muster", in: newest)
  }

  func testUnavailableOptionalFontDoesNotBlockQuestBrowsing() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchEnvironment["AETHER_UI_TESTING"] = "1"
    app.launchEnvironment["AETHER_UI_SYMBOLS"] = "1"
    app.launchEnvironment["AETHER_UI_TEST_SESSION"] = UUID().uuidString
    app.launch()
    let category = app.descendants(matching: .any).matching(identifier: "category-Quest").firstMatch
    XCTAssertTrue(category.waitForExistence(timeout: 10))
    category.click()
    let quest = app.descendants(matching: .any)["entity-Quest:4"]
    XCTAssertTrue(quest.waitForExistence(timeout: 5))
    quest.click()
    assertDisplayedText("\u{e0bf} Fixture Quest", in: app.staticTexts["entityDetailName"])
    XCTAssertTrue(app.staticTexts["Description"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.alerts.count, 0)
    app.buttons["Open Fixture Potion, Item"].click()
    XCTAssertTrue(app.buttons["Open Fixture Potion, Recipe"].waitForExistence(timeout: 5))
  }

  func testBundledPatchIsVisibleAndBrowseStartsWithHighestID() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchEnvironment["AETHER_UI_TESTING"] = "1"
    app.launchEnvironment["AETHER_UI_TEST_SESSION"] = UUID().uuidString
    app.launch()
    let patch = app.staticTexts["gameDataPatch"]
    XCTAssertTrue(patch.waitForExistence(timeout: 10))
    XCTAssertNotNil(
      ((patch.value as? String) ?? patch.label).range(
        of: #"^Game data · Patch [0-9]+\.[0-9]+(x[0-9]+)?$"#, options: .regularExpression))
    let water = app.descendants(matching: .any)["entity-Item:3"]
    let potion = app.descendants(matching: .any)["entity-Item:1"]
    XCTAssertTrue(potion.waitForExistence(timeout: 5))
    XCTAssertLessThan(water.frame.minY, potion.frame.minY)
    app.descendants(matching: .any).matching(identifier: "category-Quest").firstMatch.click()
    XCTAssertTrue(app.descendants(matching: .any)["entity-Quest:4"].waitForExistence(timeout: 5))
    XCTAssertTrue(patch.exists)
  }

  func testMouseClicksKeepHighlightAndDetailsTogether() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchEnvironment["AETHER_UI_TESTING"] = "1"
    app.launchEnvironment["AETHER_UI_TEST_SESSION"] = UUID().uuidString
    app.launch()
    let results = app.tables["entityResults"]
    let potion = results.tableRows.containing(.any, identifier: "entity-Item:1").firstMatch
    let water = results.tableRows.containing(.any, identifier: "entity-Item:3").firstMatch
    XCTAssertTrue(potion.waitForExistence(timeout: 10))
    XCTAssertTrue(water.waitForExistence(timeout: 5))
    // Icon, title, subtitle, empty space, level, and the row's vertical padding.
    for point in [
      CGVector(dx: 0.04, dy: 0.5), CGVector(dx: 0.30, dy: 0.3),
      CGVector(dx: 0.30, dy: 0.7), CGVector(dx: 0.76, dy: 0.5),
      CGVector(dx: 0.96, dy: 0.5), CGVector(dx: 0.5, dy: 0.03),
    ] {
      potion.coordinate(withNormalizedOffset: point).click()
      assertSelectedResult("Item:1", name: "Fixture Potion", in: app)
      water.coordinate(withNormalizedOffset: point).click()
      assertSelectedResult("Item:3", name: "Fixture Water", in: app)
    }
    app.typeKey(.downArrow, modifierFlags: [])
    assertSelectedResult("Item:1", name: "Fixture Potion", in: app)
    app.typeKey(.upArrow, modifierFlags: [])
    assertSelectedResult("Item:3", name: "Fixture Water", in: app)
    potion.click()
    assertSelectedResult("Item:1", name: "Fixture Potion", in: app)
    app.buttons["Open Fixture Potion, Recipe"].click()
    XCTAssertTrue(app.buttons["Open Fixture Water, Item"].waitForExistence(timeout: 5))
    // Clicking the selected row must reopen it after following a detail link.
    potion.coordinate(withNormalizedOffset: CGVector(dx: 0.76, dy: 0.5)).click()
    assertSelectedResult("Item:1", name: "Fixture Potion", in: app)
  }

  func testSavedResultSelectionFollowsClicksSortingAndHistoryReordering() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchEnvironment["AETHER_UI_TESTING"] = "1"
    app.launchEnvironment["AETHER_UI_TEST_SESSION"] = UUID().uuidString
    app.launch()
    let potion = app.descendants(matching: .any)["entity-Item:1"]
    let water = app.descendants(matching: .any)["entity-Item:3"]
    XCTAssertTrue(water.waitForExistence(timeout: 10))
    for (row, id, name) in [
      (water, "Item:3", "Fixture Water"), (potion, "Item:1", "Fixture Potion"),
    ] {
      row.click()
      assertSelectedResult(id, name: name, in: app)
      app.typeKey("d", modifierFlags: .command)
      XCTAssertTrue(app.buttons["Remove Favorite"].waitForExistence(timeout: 5))
    }
    app.descendants(matching: .any).matching(identifier: "sidebar-favorites").firstMatch.click()
    XCTAssertTrue(app.staticTexts["2 saved locally"].waitForExistence(timeout: 5))
    app.menuButtons["resultSort"].click()
    app.menuItems["Name"].click()
    water.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: 0.3)).click()
    assertSelectedResult("Item:3", name: "Fixture Water", in: app)
    potion.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: 0.7)).click()
    assertSelectedResult("Item:1", name: "Fixture Potion", in: app)
    water.rightClick()
    app.menuItems["Open Details"].click()
    assertSelectedResult("Item:3", name: "Fixture Water", in: app)
    app.menuButtons["resultSort"].click()
    app.menuItems["Original order"].click()
    app.descendants(matching: .any).matching(identifier: "sidebar-history").firstMatch.click()
    for _ in 0..<2 {
      potion.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: 0.3)).click()
      assertSelectedResult("Item:1", name: "Fixture Potion", in: app)
      water.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: 0.3)).click()
      assertSelectedResult("Item:3", name: "Fixture Water", in: app)
    }
  }

  func testQuestNumbersFollowAllFourObjectLanguages() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchEnvironment["AETHER_UI_TESTING"] = "1"
    app.launchEnvironment["AETHER_UI_TEST_SESSION"] = UUID().uuidString
    app.launchArguments = ["-AppleLocale", "sv_SE"]
    app.launch()
    let quests = app.descendants(matching: .any).matching(identifier: "category-Quest").firstMatch
    XCTAssertTrue(quests.waitForExistence(timeout: 10))
    quests.click()
    let quest = app.descendants(matching: .any)["entity-Quest:4"]
    XCTAssertTrue(quest.waitForExistence(timeout: 5))
    quest.click()
    let picker = app.descendants(matching: .any).matching(identifier: "objectLanguagePicker")
      .firstMatch
    XCTAssertTrue(picker.waitForExistence(timeout: 5))
    for (flag, experience, gil) in [
      ("🇬🇧", "224,640", "2,493"), ("🇩🇪", "224.640", "2.493"),
      ("🇫🇷", "224\u{202F}640", "2\u{202F}493"), ("🇯🇵", "224,640", "2,493"),
    ] {
      picker.radioButtons[flag].click()
      assertDisplayedText(
        experience,
        in: app.descendants(matching: .any).matching(identifier: "questReward-EXP").firstMatch)
      assertDisplayedText(
        gil, in: app.descendants(matching: .any).matching(identifier: "questReward-Gil").firstMatch)
    }
  }

  func testNumberFormattingSeparatesGlobalListsFromObjectDetails() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchEnvironment["AETHER_UI_TESTING"] = "1"
    app.launchEnvironment["AETHER_UI_TEST_SESSION"] = UUID().uuidString
    app.launchArguments = ["-AppleLocale", "sv_SE"]
    app.launch()
    let globalPicker = app.descendants(matching: .any).matching(identifier: "gameLanguagePicker")
      .firstMatch
    XCTAssertTrue(globalPicker.waitForExistence(timeout: 10))
    globalPicker.radioButtons["🇩🇪"].click()
    let row = app.descendants(matching: .any)["entity-Item:1"]
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    assertDisplayedText("i1.234", in: row)
    row.click()
    let objectPicker = app.descendants(matching: .any).matching(identifier: "objectLanguagePicker")
      .firstMatch
    XCTAssertTrue(objectPicker.waitForExistence(timeout: 5))
    assertDisplayedText(
      "9.999",
      in: app.descendants(matching: .any).matching(identifier: "metric-STACK SIZE").firstMatch)
    assertDisplayedText(
      "1.234.567 gil",
      in: app.descendants(matching: .any).matching(identifier: "metadata-Base purchase value")
        .firstMatch)
    objectPicker.radioButtons["🇫🇷"].click()
    assertDisplayedText(
      "9\u{202F}999",
      in: app.descendants(matching: .any).matching(identifier: "metric-STACK SIZE").firstMatch)
    assertDisplayedText(
      "1\u{202F}234\u{202F}567 gil",
      in: app.descendants(matching: .any).matching(identifier: "metadata-Base purchase value")
        .firstMatch)
    assertDisplayedText("i1.234", in: row)
    objectPicker.radioButtons["🇯🇵"].click()
    globalPicker.radioButtons["🇫🇷"].click()
    assertDisplayedText("i1\u{202F}234", in: row)
    assertDisplayedText(
      "9,999",
      in: app.descendants(matching: .any).matching(identifier: "metric-STACK SIZE").firstMatch)
    let recipe = app.buttons["Open フィクスチャ・ポーション, Recipe"]
    XCTAssertTrue(recipe.waitForExistence(timeout: 5))
    recipe.click()
    assertDisplayedText(
      "1\u{202F}000",
      in: app.descendants(matching: .any).matching(identifier: "metadata-Yield").firstMatch)
    assertDisplayedText(
      "1\u{202F}234",
      in: app.descendants(matching: .any).matching(identifier: "metadata-Craftsmanship required")
        .firstMatch)
    let actions = app.descendants(matching: .any).matching(identifier: "category-Action").firstMatch
    actions.click()
    let action = app.descendants(matching: .any)["entity-Action:3"]
    XCTAssertTrue(action.waitForExistence(timeout: 5))
    action.click()
    assertDisplayedText(
      "2,5 s",
      in: app.descendants(matching: .any).matching(identifier: "metadata-Cast time").firstMatch)
    assertDisplayedText(
      "60,0 s",
      in: app.descendants(matching: .any).matching(identifier: "metadata-Recast time").firstMatch)
    objectPicker.radioButtons["🇬🇧"].click()
    assertDisplayedText(
      "2.5 s",
      in: app.descendants(matching: .any).matching(identifier: "metadata-Cast time").firstMatch)
    assertDisplayedText(
      "60.0 s",
      in: app.descendants(matching: .any).matching(identifier: "metadata-Recast time").firstMatch)
  }

  func testQuestJournalReadingOrderAndRewardNavigation() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchEnvironment["AETHER_UI_TESTING"] = "1"
    app.launchEnvironment["AETHER_UI_TEST_SESSION"] = UUID().uuidString
    app.launch()
    let quests = app.descendants(matching: .any).matching(identifier: "category-Quest").firstMatch
    XCTAssertTrue(quests.waitForExistence(timeout: 10))
    quests.click()
    let quest = app.descendants(matching: .any)["entity-Quest:4"]
    XCTAssertTrue(quest.waitForExistence(timeout: 5))
    quest.click()
    let name = app.staticTexts["entityDetailName"]
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    let reward = app.staticTexts["Reward"]
    let description = app.staticTexts["Description"]
    let objectives = app.staticTexts["Objectives"]
    XCTAssertTrue(reward.exists)
    XCTAssertTrue(description.exists)
    XCTAssertTrue(objectives.exists)
    XCTAssertLessThan(name.frame.minY, reward.frame.minY)
    XCTAssertLessThan(reward.frame.minY, description.frame.minY)
    XCTAssertLessThan(description.frame.minY, objectives.frame.minY)
    XCTAssertTrue(app.staticTexts["Speak with the guildmaster."].exists)
    let item = app.buttons["Open Fixture Potion, Item"]
    XCTAssertTrue(item.exists)
    item.click()
    XCTAssertTrue(app.buttons["Open Fixture Potion, Recipe"].waitForExistence(timeout: 5))
    app.typeKey("[", modifierFlags: .command)
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Objectives"].exists)
  }
  func testObjectLanguageOverridesDefaultAndSurvivesBackNavigation() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchEnvironment["AETHER_UI_TESTING"] = "1"
    app.launchEnvironment["AETHER_UI_TEST_SESSION"] = UUID().uuidString
    app.launch()
    let row = app.descendants(matching: .any)["entity-Item:1"]
    XCTAssertTrue(row.waitForExistence(timeout: 10))
    row.click()
    let objectPicker = app.descendants(matching: .any).matching(identifier: "objectLanguagePicker")
      .firstMatch
    XCTAssertTrue(objectPicker.waitForExistence(timeout: 5))
    XCTAssertLessThan(objectPicker.frame.width, 180)
    objectPicker.radioButtons["🇯🇵"].click()
    let japaneseRecipe = app.buttons["Open フィクスチャ・ポーション, Recipe"]
    XCTAssertTrue(japaneseRecipe.waitForExistence(timeout: 5))
    let globalPicker = app.descendants(matching: .any).matching(identifier: "gameLanguagePicker")
      .firstMatch
    XCTAssertEqual(globalPicker.radioButtons["🇬🇧"].value as? Int, 1)
    globalPicker.radioButtons["🇩🇪"].click()
    XCTAssertTrue(japaneseRecipe.waitForExistence(timeout: 5))
    XCTAssertEqual(objectPicker.radioButtons["🇯🇵"].value as? Int, 1)
    japaneseRecipe.click()
    XCTAssertTrue(app.buttons["Open Fixture Wasser, Item"].waitForExistence(timeout: 5))
    XCTAssertEqual(objectPicker.radioButtons["🇩🇪"].value as? Int, 1)
    XCTAssertEqual(objectPicker.radioButtons.count, 4)
    app.typeKey("[", modifierFlags: .command)
    XCTAssertTrue(japaneseRecipe.waitForExistence(timeout: 5))
    XCTAssertEqual(objectPicker.radioButtons["🇯🇵"].value as? Int, 1)
    objectPicker.radioButtons["🇬🇧"].click()
    let englishRecipe = app.buttons["Open Fixture Potion, Recipe"]
    XCTAssertTrue(englishRecipe.waitForExistence(timeout: 5))
    globalPicker.radioButtons["🇫🇷"].click()
    XCTAssertTrue(englishRecipe.waitForExistence(timeout: 5))
    XCTAssertEqual(objectPicker.radioButtons["🇬🇧"].value as? Int, 1)
    objectPicker.radioButtons["🇫🇷"].click()
    XCTAssertTrue(app.buttons["Open Fixture Potion française, Recipe"].waitForExistence(timeout: 5))
  }

  func testLanguageToggleReloadsDataLinksAndPersistsAcrossLaunches() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchEnvironment["AETHER_UI_TESTING"] = "1"
    app.launchEnvironment["AETHER_UI_TEST_SESSION"] = UUID().uuidString
    app.launch()
    let picker = app.descendants(matching: .any).matching(identifier: "gameLanguagePicker")
      .firstMatch
    XCTAssertTrue(picker.waitForExistence(timeout: 10), app.debugDescription)
    XCTAssertEqual(picker.radioButtons.count, 4)
    XCTAssertLessThan(picker.frame.width, 180)
    let row = app.descendants(matching: .any)["entity-Item:1"]
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    row.click()
    XCTAssertTrue(app.buttons["Open Fixture Potion, Recipe"].waitForExistence(timeout: 5))
    let languages = [
      ("🇩🇪", "Fixture Heiltrank"),
      ("🇫🇷", "Fixture Potion française"),
      ("🇯🇵", "フィクスチャ・ポーション"),
      ("🇬🇧", "Fixture Potion"),
    ]
    for (language, name) in languages {
      picker.radioButtons[language].click()
      XCTAssertTrue(app.buttons["Open \(name), Recipe"].waitForExistence(timeout: 5))
      let detail = app.staticTexts["entityDetailName"]
      XCTAssertEqual((detail.value as? String) ?? detail.label, name)
    }
    picker.radioButtons["🇩🇪"].click()
    let recipe = app.buttons["Open Fixture Heiltrank, Recipe"]
    XCTAssertTrue(recipe.waitForExistence(timeout: 5))
    recipe.click()
    XCTAssertTrue(app.buttons["Open Fixture Wasser, Item"].waitForExistence(timeout: 5))
    app.typeKey("[", modifierFlags: .command)
    XCTAssertTrue(recipe.waitForExistence(timeout: 5))
    app.typeKey("f", modifierFlags: .command)
    app.searchFields.firstMatch.typeText("fixture")
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    row.click()
    XCTAssertTrue(recipe.waitForExistence(timeout: 5))
    app.terminate()
    app.launch()
    XCTAssertTrue(picker.waitForExistence(timeout: 10))
    XCTAssertEqual(picker.radioButtons["🇩🇪"].value as? Int, 1)
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    row.click()
    XCTAssertTrue(recipe.waitForExistence(timeout: 5))
  }

  func testUpdateMenuShowsAvailableVersionAndCanCheckAgain() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchEnvironment["AETHER_UI_TESTING"] = "1"
    app.launchEnvironment["AETHER_UI_TEST_SESSION"] = UUID().uuidString
    app.launch()
    let menu = app.menuBars.menuBarItems["AetherAtlas"]
    XCTAssertTrue(menu.waitForExistence(timeout: 10), app.debugDescription)
    menu.click()
    let check = app.menuItems["Check for Updates…"]
    XCTAssertTrue(check.waitForExistence(timeout: 5))
    check.click()
    let window = app.windows["Software Update"]
    XCTAssertTrue(window.waitForExistence(timeout: 5))
    XCTAssertTrue(
      window.staticTexts["Version 20991231.2359 is available."].waitForExistence(timeout: 5))
    XCTAssertTrue(window.buttons["Download Update…"].exists)
    window.buttons["Check Again"].click()
    XCTAssertTrue(
      window.staticTexts["Version 20991231.2359 is available."].waitForExistence(timeout: 5))
  }

  func testSearchDetailsRecipeKeyboardAndPersistentFavorite() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchEnvironment["AETHER_UI_TESTING"] = "1"
    app.launchEnvironment["AETHER_UI_TEST_SESSION"] = UUID().uuidString
    app.launch()
    XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 10))
    app.typeKey("f", modifierFlags: .command)
    app.searchFields.firstMatch.typeText("fixture")
    let row = app.descendants(matching: .any)["entity-Item:1"]
    XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
    row.click()
    let recipe = app.buttons["Open Fixture Potion, Recipe"]
    XCTAssertTrue(recipe.waitForExistence(timeout: 5))
    app.typeKey("d", modifierFlags: .command)
    XCTAssertTrue(app.buttons["Remove Favorite"].waitForExistence(timeout: 5))
    recipe.click()
    let ingredient = app.buttons["Open Fixture Water, Item"]
    XCTAssertTrue(ingredient.waitForExistence(timeout: 5))
    ingredient.click()
    XCTAssertTrue(app.scrollViews["entityDetail"].waitForExistence(timeout: 5))
    app.typeKey("[", modifierFlags: .command)
    XCTAssertTrue(ingredient.waitForExistence(timeout: 5))
    app.typeKey("[", modifierFlags: .command)
    XCTAssertTrue(recipe.waitForExistence(timeout: 5))
    XCTAssertEqual(app.searchFields.firstMatch.value as? String, "fixture")
    app.terminate()
    app.launch()
    let favorites = app.descendants(matching: .any).matching(identifier: "sidebar-favorites")
      .firstMatch
    XCTAssertTrue(favorites.waitForExistence(timeout: 5))
    favorites.click()
    let saved = app.descendants(matching: .any)["entity-Item:1"]
    XCTAssertTrue(saved.waitForExistence(timeout: 5))
    saved.click()
    XCTAssertTrue(recipe.waitForExistence(timeout: 5))
  }
  func testEmptySearchAndEscape() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchEnvironment["AETHER_UI_TESTING"] = "1"
    app.launchEnvironment["AETHER_UI_TEST_SESSION"] = UUID().uuidString
    app.launch()
    XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 10))
    XCTAssertTrue(app.descendants(matching: .any)["entity-Item:1"].waitForExistence(timeout: 5))
    let heading = app.staticTexts["resultsHeading"]
    let count = app.staticTexts["resultsCount"]
    let top = heading.frame.minY
    let bottom = count.frame.maxY
    let sortRight = app.menuButtons["resultSort"].frame.maxX
    app.typeKey("f", modifierFlags: .command)
    app.searchFields.firstMatch.typeText("no-results")
    XCTAssertTrue(app.staticTexts["No matching entities"].waitForExistence(timeout: 5))
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Empty results column"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    XCTAssertEqual(heading.frame.minY, top, accuracy: 1)
    XCTAssertEqual(count.frame.maxY, bottom, accuracy: 1)
    XCTAssertEqual(app.menuButtons["resultSort"].frame.maxX, sortRight, accuracy: 1)
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertEqual(app.searchFields.firstMatch.value as? String, "")
    XCTAssertTrue(app.descendants(matching: .any)["entity-Item:1"].waitForExistence(timeout: 5))
    for (sidebar, message) in [
      ("sidebar-favorites", "Keep your discoveries"),
      ("sidebar-history", "Your journey starts here"),
    ] {
      app.descendants(matching: .any).matching(identifier: sidebar).firstMatch.click()
      XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 5))
      XCTAssertEqual(heading.frame.minY, top, accuracy: 1)
      XCTAssertEqual(count.frame.maxY, bottom, accuracy: 1)
      XCTAssertEqual(app.menuButtons["resultSort"].frame.maxX, sortRight, accuracy: 1)
    }
  }
  func testFormattedActionDescriptionIsNativeReadableText() {
    let app = XCUIApplication()
    app.launchEnvironment["AETHER_UI_TESTING"] = "1"
    app.launchEnvironment["AETHER_UI_TEST_SESSION"] = UUID().uuidString
    app.launch()
    let actions = app.descendants(matching: .any).matching(identifier: "category-Action").firstMatch
    XCTAssertTrue(actions.waitForExistence(timeout: 10))
    actions.click()
    let sprint = app.descendants(matching: .any)["entity-Action:3"]
    XCTAssertTrue(sprint.waitForExistence(timeout: 5))
    sprint.click()
    let description = app.staticTexts.matching(identifier: "gameDescription").firstMatch
    XCTAssertTrue(description.waitForExistence(timeout: 5))
    let text = (description.value as? String) ?? description.label
    XCTAssertEqual(text, "Increases movement speed.\nAdditional Effect: Grants Jog.")
    XCTAssertFalse(text.contains("<span"))
  }

}
