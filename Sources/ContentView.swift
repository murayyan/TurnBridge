import SwiftUI
import MapKit

enum TravelMode: String, CaseIterable, Hashable {
    case car, walk

    var transport: MKDirectionsTransportType {
        self == .car ? .automobile : .walking
    }

    var label: String {
        self == .car ? "Mobil" : "Jalan"
    }
}

struct ContentView: View {
    @EnvironmentObject private var engine: NavigationEngine
    @State private var query: String = ""
    @State private var results: [MKMapItem] = []
    @State private var isSearching = false
    @State private var mode: TravelMode = .car

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.07, green: 0.08, blue: 0.10).ignoresSafeArea()

                VStack(spacing: 16) {
                    header
                    activeCard
                    searchBar

                    if !results.isEmpty {
                        resultList
                    } else {
                        Spacer()
                        instructionsCard
                        Spacer()
                    }

                    testButton
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            .navigationBarHidden(true)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("TurnBridge")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                Text("Navigasi Apple Maps → Huawei Fit 3")
                    .font(.system(size: 11))
                    .foregroundColor(Color(red: 0.6, green: 0.65, blue: 0.75))
            }
            Spacer()
            Circle()
                .fill(engine.isRunning ? Color.green : Color.gray.opacity(0.4))
                .frame(width: 10, height: 10)
        }
    }

    private var activeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(engine.status.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundColor(engine.isRunning ? Color.green : Color(red: 0.7, green: 0.7, blue: 0.7))
                Spacer()
                if !engine.summary.isEmpty {
                    Text(engine.summary)
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 0.6, green: 0.65, blue: 0.75))
                }
            }

            if engine.isRunning {
                HStack(alignment: .firstTextBaseline) {
                    Text(engine.nextInstruction)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    Spacer()
                    if !engine.nextDistance.isEmpty {
                        Text(engine.nextDistance)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(Color(red: 1.0, green: 0.62, blue: 0.11))
                    }
                }

                if !engine.remainingText.isEmpty {
                    Text(engine.remainingText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(red: 0.65, green: 0.85, blue: 0.7))
                }

                Button(action: { engine.stop() }) {
                    Text("Hentikan Navigasi")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(8)
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .background(Color(red: 0.12, green: 0.14, blue: 0.18))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(engine.isRunning ? Color.green.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var searchBar: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                TextField("Cari tujuan (nama tempat, jalan)...", text: $query)
                    .foregroundColor(.white)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .onSubmit { search() }

                if !query.isEmpty {
                    Button(action: { query = ""; results = [] }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(12)
            .background(Color(red: 0.14, green: 0.16, blue: 0.20))
            .cornerRadius(10)

            HStack(spacing: 8) {
                Picker("Mode", selection: $mode) {
                    ForEach(TravelMode.allCases, id: \.self) { item in
                        Text(item.label).tag(item)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())

                Button(action: { _ = engine.startFromClipboard() }) {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.on.clipboard")
                        Text("Tempel")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(red: 0.18, green: 0.34, blue: 0.24))
                    .cornerRadius(8)
                }
            }

            Text("Dari Apple Maps: buka tempat → Bagikan → Salin → tekan Tempel")
                .font(.system(size: 10))
                .foregroundColor(Color(red: 0.5, green: 0.55, blue: 0.65))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var resultList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(results, id: \.self) { item in
                    Button(action: { start(item) }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name ?? "Tujuan")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                Text(item.placemark.title ?? "")
                                    .font(.system(size: 11))
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(Color(red: 1.0, green: 0.62, blue: 0.11))
                        }
                        .padding(12)
                        .background(Color(red: 0.14, green: 0.16, blue: 0.20))
                        .cornerRadius(10)
                    }
                }
            }
        }
    }

    private var instructionsCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.turn.up.right.circle")
                .font(.system(size: 36))
                .foregroundColor(Color(red: 1.0, green: 0.62, blue: 0.11))
                .padding(.bottom, 4)
            Text("Cara Pakai")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
            Text("1. Cari tujuan di atas dan pilih rute.\n2. Kunci layar iPhone dan masukkan ke saku.\n3. Tiap mendekati belokan (~150m), Watch Fit 3 akan bergetar dan menampilkan nama jalan.")
                .font(.system(size: 12))
                .foregroundColor(Color(red: 0.7, green: 0.72, blue: 0.78))
                .multilineTextAlignment(.leading)
                .lineSpacing(4)
            Text(engine.authorizationText)
                .font(.system(size: 10))
                .foregroundColor(Color(red: 0.5, green: 0.55, blue: 0.65))
                .padding(.top, 4)
        }
        .padding(18)
        .background(Color(red: 0.11, green: 0.13, blue: 0.17))
        .cornerRadius(12)
    }

    private var testButton: some View {
        Button(action: { engine.testNotification() }) {
            HStack {
                Image(systemName: "bell.badge.fill")
                Text("Tes Notifikasi ke Jam Sekarang")
                    .fontWeight(.bold)
            }
            .font(.system(size: 13))
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(red: 1.0, green: 0.62, blue: 0.11))
            .cornerRadius(10)
        }
    }

    private func search() {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = query
        MKLocalSearch(request: req).start { resp, _ in
            isSearching = false
            results = resp?.mapItems ?? []
        }
    }

    private func start(_ item: MKMapItem) {
        results = []
        query = item.name ?? ""
        engine.start(destination: item, transport: mode.transport)
    }
}
