import XCTest

@MainActor final class BrowserUITests: XCTestCase {
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
