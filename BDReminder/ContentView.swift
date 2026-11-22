//
//  ContentView.swift
//  BDReminder — 根视图：底部五标签
//  所有功能视图都定义在 BDReminderApp.swift（即工作区 BirthdayApp.swift）里。
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label(L("首页"), systemImage: "house.fill")
                }

            ContactListView()
                .tabItem {
                    Label(L("联系人"), systemImage: "person.2.fill")
                }

            NavigationStack {
                CardMakerView()
            }
            .tabItem {
                Label(L("做卡片"), systemImage: "paintbrush.pointed.fill")
            }

            CardLibraryView()
                .tabItem {
                    Label(L("卡片库"), systemImage: "rectangle.stack.fill")
                }

            SettingsView()
                .tabItem {
                    Label(L("设置"), systemImage: "gearshape.fill")
                }
        }
        .tint(AppTheme.sunnyDeep)
        .fontDesign(.rounded)
        .toolbarBackground(AppTheme.sunny, for: .tabBar)
        .toolbarBackgroundVisibility(.visible, for: .tabBar)
    }
}
