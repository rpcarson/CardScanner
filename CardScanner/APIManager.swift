//
//  APIManager.swift
//  CardScanner
//
//  Created by Reed Carson on 5/18/18.
//  Copyright © 2018 Reed Carson. All rights reserved.
//

import Foundation


struct APIConstants {
    static let authEndpoint = "https://api.tcgplayer.com/token"
    static let productIdLookupEndpoint = "http://api.tcgplayer.com/v1.8.1/pricing/product/"
    static let publicKey = "3E110245-55AA-4358-8881-083C8436450B" //client_id
    static let privateKey = "58CB2CFA-2CAA-49F2-A135-03C493F511FA" //client_secret
}


class ApiManager {
    
    typealias Completion<T> = ((ApiResult<T>) -> Void)
    
    enum RequestType {
        case productIdLookup
    }
    
    enum ApiResult<T> {
        case success(T)
        case error(Error)
    }
    
    let authEndpoint = "https://api.tcgplayer.com/token"
    var publicKey = "3E110245-55AA-4358-8881-083C8436450B" //client_id
    var privateKey = "58CB2CFA-2CAA-49F2-A135-03C493F511FA" //client_secret
    var applicationID = 2182
    var accessToken: String  = "Et5wftoKJQZd38eUvYyzANI2ezY5yzoU2rz6JEhP_k4foLV9JKUEULsSJh5k7ohopVpCeKZid3LRgfFSCkBvjgNUpF15Mszmi7XWXNb2LGHapWaRgh3Im8AXobpH7f567TbrfDQsp8lOMNg1JPeQtTIwX8IXlIjM5bbehK-1UyWct7NIj-lAPTphQ2043_-MdxG8d4cLsr3mDZZQev7w3THR3jkYcBvbrGKyHRdIYdAxTt9Rt359EE6gSG7xAo91Mkoc-T-cPuuAxe7wJBVB78mwOhglXb-Q9hFTtNWWL9l2nU3lmABLpSVCdp6uRPF09tSUTw" //BEARER_TOKEN
   
    var tokenExpiration: Double?
    var isExpired: Bool {
        return tokenExpiration != nil ?
                Date().timeIntervalSince1970 > tokenExpiration! :
                true
    }
    
    let testRequestProdutName = "http://api.tcgplayer.com/catalog/products?productName=Bloodcrazed%20Paladin"
    
    let testProductID = "142008"
    
    func getPriceForProductID(_ productId: String, _ completion: @escaping Completion<[String:Any]>) {
        guard let url = URL(string: testRequestProdutName) else {
            let error = NSError(domain: "could not get url for product id", code: 1, userInfo: nil)
            print("could not get url for product id")
            completion(ApiResult.error(error))
            return
        }
        
        let session = URLSession(configuration: .default)
        var request = URLRequest(url: url)
        request.setValue("Accept: application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpMethod = "GET"
        
        runDataTaskWithRequest(request, session: session) { (result) in
            completion(result)
        }
    }
    
    private func requestAuthorization(_ completion: @escaping Completion<[String:Any]>) {
        guard let url = URL(string: authEndpoint) else {
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
