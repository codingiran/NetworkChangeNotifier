# NetworkChangeNotifier

### Repo
https://github.com/codingiran/NetworkChangeNotifier

### Use

```swift

// create instance
private let networkChangeNotifier = NetworkChangeNotifier(queue: .main, debouncerDelay: .milliseconds(2500))

// start listen
networkChangeNotifier.start { [weak self] interface in
    // get interface change notification 
}

// get current interface
let currentInterface = networkChangeNotifier.currentInterface

// get current interface name
let currentInterfaceName = networkChangeNotifier.currentBSDName

```
