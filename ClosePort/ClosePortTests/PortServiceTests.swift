import XCTest
@testable import ClosePort

final class PortServiceTests: XCTestCase {

    var sut: PortService!

    override func setUp() {
        super.setUp()
        sut = PortService()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - parseLsofOutput Tests

    func test_parseLsofOutput_withValidOutput_returnsPorts() {
        let output = """
        COMMAND     PID   USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        node      41755 junior   15u  IPv6 0x3133d383cd204d64      0t0  TCP *:8080 (LISTEN)
        redis-ser   748 junior    6u  IPv4 0xc1928f23ed27aa69      0t0  TCP 127.0.0.1:6379 (LISTEN)
        """

        let ports = sut.parseLsofOutput(output)

        XCTAssertEqual(ports.count, 2)
        XCTAssertEqual(ports[0].port, 6379)
        XCTAssertEqual(ports[0].command, "redis-ser")
        XCTAssertEqual(ports[0].pid, 748)
        XCTAssertEqual(ports[0].address, "localhost")
        XCTAssertEqual(ports[1].port, 8080)
        XCTAssertEqual(ports[1].command, "node")
        XCTAssertEqual(ports[1].address, "0.0.0.0")
    }

    func test_parseLsofOutput_withNilOutput_returnsEmptyArray() {
        let ports = sut.parseLsofOutput(nil)

        XCTAssertTrue(ports.isEmpty)
    }

    func test_parseLsofOutput_withEmptyOutput_returnsEmptyArray() {
        let ports = sut.parseLsofOutput("")

        XCTAssertTrue(ports.isEmpty)
    }

    func test_parseLsofOutput_withOnlyHeader_returnsEmptyArray() {
        let output = "COMMAND     PID   USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME"

        let ports = sut.parseLsofOutput(output)

        XCTAssertTrue(ports.isEmpty)
    }

    func test_parseLsofOutput_skipsDuplicatePorts() {
        let output = """
        COMMAND     PID   USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        redis-ser   748 junior    6u  IPv4 0xc1928f23ed27aa69      0t0  TCP 127.0.0.1:6379 (LISTEN)
        redis-ser   748 junior    7u  IPv6 0xd85a5d6c07243d35      0t0  TCP [::1]:6379 (LISTEN)
        """

        let ports = sut.parseLsofOutput(output)

        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports[0].port, 6379)
    }

    func test_parseLsofOutput_sortsPortsByNumber() {
        let output = """
        COMMAND     PID   USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        node      100 junior   15u  IPv4 0x123      0t0  TCP *:8080 (LISTEN)
        python    200 junior   10u  IPv4 0x456      0t0  TCP *:3000 (LISTEN)
        ruby      300 junior   20u  IPv4 0x789      0t0  TCP *:5000 (LISTEN)
        """

        let ports = sut.parseLsofOutput(output)

        XCTAssertEqual(ports[0].port, 3000)
        XCTAssertEqual(ports[1].port, 5000)
        XCTAssertEqual(ports[2].port, 8080)
    }

    func test_parseLsofOutput_handlesIPv6Addresses() {
        let output = """
        COMMAND     PID   USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        node      100 junior   15u  IPv6 0x123      0t0  TCP [::1]:3000 (LISTEN)
        """

        let ports = sut.parseLsofOutput(output)

        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports[0].port, 3000)
        XCTAssertEqual(ports[0].address, "localhost")
    }

    func test_parseLsofOutput_handlesWildcardAddress() {
        let output = """
        COMMAND     PID   USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        node      100 junior   15u  IPv4 0x123      0t0  TCP *:8080 (LISTEN)
        """

        let ports = sut.parseLsofOutput(output)

        XCTAssertEqual(ports[0].address, "0.0.0.0")
    }

    func test_parseLsofOutput_filtersExcludedApps() {
        let output = """
        COMMAND     PID   USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        Spotify     856 junior   72u  IPv4 0xbe7928f920d19cc1      0t0  TCP 127.0.0.1:7768 (LISTEN)
        node      100 junior   15u  IPv4 0x123      0t0  TCP *:3000 (LISTEN)
        """

        let ports = sut.parseLsofOutput(output)

        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports[0].command, "node")
    }

    func test_parseLsofOutput_filtersNonDevPorts() {
        let output = """
        COMMAND     PID   USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        someapp   100 junior   15u  IPv4 0x123      0t0  TCP *:63 (LISTEN)
        node      200 junior   15u  IPv4 0x456      0t0  TCP *:3000 (LISTEN)
        """

        let ports = sut.parseLsofOutput(output)

        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports[0].port, 3000)
    }
}
