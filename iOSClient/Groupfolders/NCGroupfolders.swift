//
//  NCGroupfolders.swift
//  Nextcloud
//
//  Created by Marino Faggiana on 14/04/2023.
//  Copyright © 2023 Marino Faggiana. All rights reserved.
//
//  Author Marino Faggiana <marino.faggiana@nextcloud.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import UIKit
import NextcloudKit

class NCGroupfolders: NCCollectionViewCommon {

    // MARK: - View Life Cycle

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)

        titleCurrentFolder = NSLocalizedString("_group_folders_", comment: "")
        layoutKey = NCGlobal.shared.layoutViewGroupfolders
        enableSearchBar = false
        headerMenuButtonsView = true
        headerRichWorkspaceDisable = true
        emptyImage = UIImage(named: "folder_group")?.image(color: NCBrandColor.shared.brandElement, size: UIScreen.main.bounds.width)
        emptyTitle = "_files_no_files_"
        emptyDescription = "_tutorial_groupfolders_view_"
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        navigationController?.setFileAppreance()
    }

    // MARK: - DataSource + NC Endpoint

    override func queryDB(isForced: Bool) {

        var metadatas: [tableMetadata] = []

        if self.serverUrl.isEmpty {
            metadatas = NCManageDatabase.shared.getMetadatasFromGroupfolders(account: self.appDelegate.account, urlBase: self.appDelegate.urlBase, userId: self.appDelegate.userId)
        } else {
            metadatas = NCManageDatabase.shared.getMetadatas(predicate: NSPredicate(format: "account == %@ AND serverUrl == %@", self.appDelegate.account, self.serverUrl))
        }

        self.dataSource = NCDataSource(
            metadatas: metadatas,
            account: self.appDelegate.account,
            sort: self.layoutForView?.sort,
            ascending: self.layoutForView?.ascending,
            directoryOnTop: self.layoutForView?.directoryOnTop,
            favoriteOnTop: true,
            filterLivePhoto: true,
            groupByField: self.groupByField,
            providers: self.providers,
            searchResults: self.searchResults)
    }

    override func reloadDataSource(isForced: Bool = true) {
        super.reloadDataSource()

        self.queryDB(isForced: isForced)
        DispatchQueue.main.async {
            self.isReloadDataSourceNetworkInProgress = false
            self.refreshControl.endRefreshing()
            self.collectionView.reloadData()
        }
    }

    override func reloadDataSourceNetwork(isForced: Bool = false) {
        super.reloadDataSourceNetwork(isForced: isForced)

        NextcloudKit.shared.nkCommonInstance.writeLog("[INFO] Reload data source network groupfolders forced \(isForced)")

        isReloadDataSourceNetworkInProgress = true
        collectionView?.reloadData()

        let homeServerUrl = NCUtilityFileSystem.shared.getHomeServer(urlBase: self.appDelegate.urlBase, userId: self.appDelegate.userId)

        NextcloudKit.shared.getGroupfolders(options: NKRequestOptions(queue: NextcloudKit.shared.nkCommonInstance.backgroundQueue)) { account, results, _, error in

            if error == .success, let groupfolders = results {
                NCManageDatabase.shared.addGroupfolders(account: account, groupfolders: groupfolders)
                Task {
                    for groupfolder in groupfolders {
                        let mountPoint = groupfolder.mountPoint.hasPrefix("/") ? groupfolder.mountPoint : "/" + groupfolder.mountPoint
                        let serverUrlFileName = homeServerUrl + mountPoint
                        if NCManageDatabase.shared.getMetadataFromDirectory(account: self.appDelegate.account, serverUrl: serverUrlFileName) == nil {
                            let results = await NextcloudKit.shared.readFileOrFolder(serverUrlFileName: serverUrlFileName, depth: "0", showHiddenFiles: CCUtility.getShowHiddenFiles())
                            if results.error == .success, let file = results.files.first {
                                let isDirectoryE2EE = NCUtility.shared.isDirectoryE2EE(file: file)
                                let metadata = NCManageDatabase.shared.convertFileToMetadata(file, isDirectoryE2EE: isDirectoryE2EE)
                                NCManageDatabase.shared.addMetadata(metadata)
                                NCManageDatabase.shared.addDirectory(encrypted: isDirectoryE2EE, favorite: metadata.favorite, ocId: metadata.ocId, fileId: metadata.fileId, etag: nil, permissions: metadata.permissions, serverUrl: serverUrlFileName, account: metadata.account)
                            }
                        }
                    }
                    self.reloadDataSource()
                }
            } else if error != .success {
                self.reloadDataSource()
            }
        }
    }
}
