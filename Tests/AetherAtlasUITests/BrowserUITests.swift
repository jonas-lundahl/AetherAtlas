import XCTest

@MainActor final class BrowserUITests: XCTestCase {
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
    let app = XCUIApplication()
    app.launchEnvironment["AETHER_UI_TESTING"] = "1"
    app.launchEnvironment["AETHER_UI_TEST_SESSION"] = UUID().uuidString
    app.launch()
    XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 10))
    app.typeKey("f", modifierFlags: .command)
    app.searchFields.firstMatch.typeText("no-results")
    XCTAssertTrue(app.staticTexts["No matching entities"].waitForExistence(timeout: 5))
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertEqual(app.searchFields.firstMatch.value as? String, "")
    XCTAssertTrue(app.descendants(matching: .any)["entity-Item:1"].waitForExistence(timeout: 5))
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
