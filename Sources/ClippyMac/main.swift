import Foundation

// точка входа: сперва возможный self-check (без запуска GUI, дружит с headless CI),
// затем само приложение
runSelfCheckIfRequested()
ClippyMacApp.main()
