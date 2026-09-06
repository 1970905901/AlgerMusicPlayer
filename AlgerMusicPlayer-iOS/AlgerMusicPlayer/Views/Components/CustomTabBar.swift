import SwiftUI

struct CustomTabBar: View {
    @Binding var selected: Tab
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                Button {
                    selected = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon).font(.system(size: 21))
                        Text(tab.title).font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(selected == tab ? .accentColor : .secondary)
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(.bar)
    }
}
