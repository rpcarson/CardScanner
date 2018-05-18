//
//  APIManager.swift
//  CardScanner
//
//  Created by Reed Carson on 5/18/18.
//  Copyright © 2018 Reed Carson. All rights reserved.
//

import Foundation


class ApiManager {
    var publicKey = "3E110245-55AA-4358-8881-083C8436450B" //client_id
    var privateKey = "58CB2CFA-2CAA-49F2-A135-03C493F511FA" //client_secret
    var applicationID = 2182
    var accessToken: String? = "Et5wftoKJQZd38eUvYyzANI2ezY5yzoU2rz6JEhP_k4foLV9JKUEULsSJh5k7ohopVpCeKZid3LRgfFSCkBvjgNUpF15Mszmi7XWXNb2LGHapWaRgh3Im8AXobpH7f567TbrfDQsp8lOMNg1JPeQtTIwX8IXlIjM5bbehK-1UyWct7NIj-lAPTphQ2043_-MdxG8d4cLsr3mDZZQev7w3THR3jkYcBvbrGKyHRdIYdAxTt9Rt359EE6gSG7xAo91Mkoc-T-cPuuAxe7wJBVB78mwOhglXb-Q9hFTtNWWL9l2nU3lmABLpSVCdp6uRPF09tSUTw" //BEARER_TOKEN
    var bearerToken: String?
    
    let authEndpoint = "https://api.tcgplayer.com/token"

    func request() {
        guard let url = URL(string: authEndpoint) else {
            print("bad url")
            return
        }
        
        let session = URLSession(configuration: .default)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let data = "grant_type=client_credentials&client_id=\(publicKey)&client_secret=\(privateKey)"
        request.httpBody = data.data(using: .utf8, allowLossyConversion: true)
        
        let task = session.dataTask(with: request) { (data, response, error) in
            if let error = error {
                print(error)
            }
            
            if let data = data {
                do {
                    let json = try JSONSerialization.jsonObject(with: data, options: .allowFragments)
                    
                    print("results \(json)")
                    print("")
                } catch let error {
                    print("serialization error \(error)")
                }
            }
        }
        
        task.resume()
       // request.http
      //  request.addValue("ACCESS_TOKEN", forHTTPHeaderField: "X-Tcg-Access-Token")
      //  request.httpBody = "grant_type=client_credentials&client_id=\(publicKey)&client_secret=\(privateKey)"
       // request.setValue("X-Tcg-Access-Token: ACCESS_TOKEN", forHTTPHeaderField: )
    }
    
}
