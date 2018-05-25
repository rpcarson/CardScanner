//
//  APIManager.swift
//  CardScanner
//
//  Created by Reed Carson on 5/18/18.
//  Copyright © 2018 Reed Carson. All rights reserved.
//

import Foundation

let testRequestProdutName = "http://api.tcgplayer.com/catalog/products?productName=Bloodcrazed%20Paladin"

let testProductID = "142008"


struct APIConstants {
    static let authEndpoint = "https://api.tcgplayer.com/token"
    static let productIdLookupEndpoint = "http://api.tcgplayer.com/v1.8.1/pricing/product/"
    static let publicKey = "3E110245-55AA-4358-8881-083C8436450B" //client_id
    static let privateKey = "58CB2CFA-2CAA-49F2-A135-03C493F511FA" //client_secret
    static let searchByName = "http://api.tcgplayer.com/catalog/products?productName="
}

enum RequestType {
    case productIdLookup
}

enum ApiResult<T> {
    case success(T)
    case error(Error)
}


class ApiManager {
    
    typealias Completion<T> = ((ApiResult<T>) -> Void)
    
   
    
    private var publicKey = "3E110245-55AA-4358-8881-083C8436450B" //client_id
    private var privateKey = "58CB2CFA-2CAA-49F2-A135-03C493F511FA" //client_secret
    private var applicationID = 2182
    private var accessToken: String  = "Et5wftoKJQZd38eUvYyzANI2ezY5yzoU2rz6JEhP_k4foLV9JKUEULsSJh5k7ohopVpCeKZid3LRgfFSCkBvjgNUpF15Mszmi7XWXNb2LGHapWaRgh3Im8AXobpH7f567TbrfDQsp8lOMNg1JPeQtTIwX8IXlIjM5bbehK-1UyWct7NIj-lAPTphQ2043_-MdxG8d4cLsr3mDZZQev7w3THR3jkYcBvbrGKyHRdIYdAxTt9Rt359EE6gSG7xAo91Mkoc-T-cPuuAxe7wJBVB78mwOhglXb-Q9hFTtNWWL9l2nU3lmABLpSVCdp6uRPF09tSUTw" //BEARER_TOKEN
   
    var tokenExpiration: Double?
    var isExpired: Bool {
        return tokenExpiration != nil ?
                Date().timeIntervalSince1970 > tokenExpiration! :
                true
    }
    
    func getPriceForName(_ name: String, _ completion: @escaping Completion<[String:Any]>) {
        getProductIdForName(name) { (result) in
            switch result {
            case .success(let id):
                self.getPriceForProductID(String(id), { (result) in
                    switch result {
                    case .success(let json):
                        completion(ApiResult.success(json))
                    case .error(let error):
                        completion(ApiResult.error(error))
                    }
                })
            case .error(let error):
                completion(ApiResult.error(error))
            }
        }
    }
    
    func getProductIdForName(_ name: String, _ completion: @escaping Completion<Int>) {
        guard let escapedName = name.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              let url = URL(string: APIConstants.searchByName + escapedName) else {
            let error = NSError(domain: "could not get url for product id", code: 1, userInfo: nil)
            print("could not get url for product id")
            completion(ApiResult.error(error))
            return
        }
        
        let session = URLSession(configuration: .default)
        let request = getRequestForLookup(url)
        
        runDataTaskWithRequest(request, session: session) { (result) in
            switch result {
            case .success(let json):
                if let id = self.getProductIdForJson(json) {
                    completion(ApiResult.success(id))
                } else {
                    let error = NSError(domain: "Could not get product id for name search", code: 2, userInfo: nil)
                    completion(ApiResult.error(error))
                }
            case .error(let error):
                completion(ApiResult.error(error))
            }
        }
    }
    
    func getPriceForProductID(_ productId: String, _ completion: @escaping Completion<[String:Any]>) {
        guard let url = URL(string: "http://api.tcgplayer.com/pricing/product/\(productId)") else {
            let error = NSError(domain: "could not get url for product id", code: 1, userInfo: nil)
            print("could not get url for product id")
            completion(ApiResult.error(error))
            return
        }
        
        let session = URLSession(configuration: .default)
        let request = getRequestForLookup(url)
        
        runDataTaskWithRequest(request, session: session) { (result) in
            completion(result)
        }
    }
    
    private func getRequestForLookup(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Accept: application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpMethod = "GET"
        return request
    }
    
    private func requestAuthorization(_ completion: @escaping Completion<[String:Any]>) {
        guard let url = URL(string: APIConstants.authEndpoint) else {
            let error = NSError(domain: "bad url", code: 1, userInfo: nil)
            print("bad url")
            completion(ApiResult.error(error))
            return
        }
        
        let session = URLSession(configuration: .default)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let data = "grant_type=client_credentials&client_id=\(publicKey)&client_secret=\(privateKey)"
        request.httpBody = data.data(using: .utf8, allowLossyConversion: true)
        
        runDataTaskWithRequest(request, session: session) { (result) in
            completion(result)
        }
    }
    
    private func getProductIdForJson(_ json: [String:Any]) -> Int? {
        if let results = json["results"] as? [[String:Any]] {
            if let resultOne = results[safe: 0] {
                if let id = resultOne["productId"] as? Int {
                    print("PRODUCT ID \(id)")
                    return id
                }
            }
        }
        return nil
    }
    
    private func runDataTaskWithRequest(_ request: URLRequest, session: URLSession, _ completion: @escaping Completion<[String:Any]>) {
        let task = session.dataTask(with: request) { (data, response, error) in
            if let error = error {
                completion(ApiResult.error(error))
                print("error for price request: \(error)")
                return
            }
            
            if let data = data {
                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String:Any] {
                        print("results \(json)")
                        completion(ApiResult.success(json))
                    }
                } catch let error {
                    print("serialization error \(error)")
                    completion(ApiResult.error(error))
                }
            }
        }
        task.resume()
    }
    
}
