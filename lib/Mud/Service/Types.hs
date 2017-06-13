{-# LANGUAGE DataKinds, DeriveGeneric, GeneralizedNewtypeDeriving, TypeOperators #-}

module Mud.Service.Types where

import Mud.Data.State.MudData
import Mud.Misc.Database

import Data.Aeson (FromJSON(..), ToJSON(..))
import Data.Text (Text)
import GHC.Generics (Generic)
import Servant (Capture, DeleteNoContent, FromHttpApiData, Get, Header, Headers, JSON, NoContent, PostNoContent, ReqBody, ToHttpApiData, (:<|>)(..), (:>))
import Servant.Auth.Server (Auth, FromJWT, SetCookie, ToJWT)


type API auths = (Auth auths Login :> Protected) :<|> Unprotected


data Login = Login { username :: Text
                   , password :: Text } deriving Generic


instance FromJSON Login
instance ToJSON   Login
instance FromJWT  Login
instance ToJWT    Login


type Protected =
       "pla"                                               :> Get             '[JSON] (Object Pla)
  -- ==========
  :<|> "pla"                 :> "all"                      :> Get             '[JSON] [Object Pla]
  -----
  :<|> "db" :> "alertexec"   :> "all"                      :> Get             '[JSON] [AlertExecRec]
  :<|> "db" :> "alertexec"   :> Capture "id" CaptureInt    :> DeleteNoContent '[JSON] NoContent
  -----
  :<|> "db" :> "alertmsg"    :> "all"                      :> Get             '[JSON] [AlertMsgRec]
  :<|> "db" :> "alertmsg"    :> Capture "id" CaptureInt    :> DeleteNoContent '[JSON] NoContent
  -----
  :<|> "db" :> "banhost"     :> "all"                      :> Get             '[JSON] [BanHostRec]
  :<|> "db" :> "banhost"     :> ReqBody '[JSON] BanHostRec :> PostNoContent   '[JSON] NoContent
  :<|> "db" :> "banhost"     :> Capture "id" CaptureInt    :> DeleteNoContent '[JSON] NoContent
  -----
  :<|> "db" :> "banpc"       :> "all"                      :> Get             '[JSON] [BanPCRec]
  :<|> "db" :> "banpc"       :> ReqBody '[JSON] BanPCRec   :> PostNoContent   '[JSON] NoContent
  :<|> "db" :> "banpc"       :> Capture "id" CaptureInt    :> DeleteNoContent '[JSON] NoContent
  -----
  :<|> "db" :> "bug"         :> "all"                      :> Get             '[JSON] [BugRec]
  :<|> "db" :> "bug"         :> Capture "id" CaptureInt    :> DeleteNoContent '[JSON] NoContent
  -----
  :<|> "db" :> "discover"    :> "all"                      :> Get             '[JSON] [DiscoverRec]
  :<|> "db" :> "discover"    :> "all"                      :> DeleteNoContent '[JSON] NoContent
  -----
  :<|> "db" :> "prof"        :> "all"                      :> Get             '[JSON] [ProfRec]
  :<|> "db" :> "prof"        :> "all"                      :> DeleteNoContent '[JSON] NoContent
  -----
  :<|> "db" :> "propname"    :> "all"                      :> Get             '[JSON] [PropNameRec]
  :<|> "db" :> "propname"    :> "all"                      :> DeleteNoContent '[JSON] NoContent
  -----
  :<|> "db" :> "telnetchars" :> "all"                      :> Get             '[JSON] [TelnetCharsRec]
  :<|> "db" :> "telnetchars" :> "all"                      :> DeleteNoContent '[JSON] NoContent
  -----
  :<|> "db" :> "ttype"       :> "all"                      :> Get             '[JSON] [TTypeRec]
  :<|> "db" :> "ttype"       :> "all"                      :> DeleteNoContent '[JSON] NoContent
  -----
  :<|> "db" :> "typo"        :> "all"                      :> Get             '[JSON] [TypoRec]
  :<|> "db" :> "typo"        :> Capture "id" CaptureInt    :> DeleteNoContent '[JSON] NoContent
  -----
  :<|> "db" :> "word"        :> "all"                      :> Get             '[JSON] [WordRec]
  :<|> "db" :> "word"        :> "all"                      :> DeleteNoContent '[JSON] NoContent


data Object a = Object { objectId :: Id
                       , object   :: a } deriving Generic


instance (ToJSON   a) => ToJSON   (Object a)
instance (FromJSON a) => FromJSON (Object a)


newtype CaptureInt = CaptureInt { fromCaptureInt :: Int } deriving (FromHttpApiData, ToHttpApiData)


type Unprotected =
       "login" :> ReqBody       '[JSON] Login
               :> PostNoContent '[JSON] (Headers '[ Header "Set-Cookie" SetCookie
                                                  , Header "Set-Cookie" SetCookie ] NoContent)
